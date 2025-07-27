#include <hwloc.h>
#include <sys/time.h>
#include <xbt/log.h>
#include <vector>
#include <sstream>
#include <sys/resource.h> // For getrusage
#include <fstream>
#include <immintrin.h>  // For intrinsics
#include <iostream>

XBT_LOG_NEW_DEFAULT_CATEGORY(example, "example");

// Buffer aligned to cache line size (typically 64 bytes)
#define CACHE_LINE_SIZE 64
#define ALIGNED __attribute__((aligned(CACHE_LINE_SIZE)))

struct thread_locality_s
{
    int numa_id;
    int core_id;
    long voluntary_context_switches;
    long involuntary_context_switches;
    long core_migrations;
};
typedef struct thread_locality_s thread_locality_t;

double get_time_us();

void* create_dram_buffer(size_t size);
void dram_write(void* dest, const void* src, size_t size);
void dram_read(void* dest, const void* src, size_t size);

std::string join(const std::vector<int> &vec, const std::string &delimiter=",");
std::vector<int> thread_numa_get(hwloc_topology_t topology, char *address, size_t size);
thread_locality_t thread_get_locality_from_os(hwloc_topology_t topology);

int main(int argc, char *argv[])
{
    // Initialize XBT logging system
    xbt_log_init(&argc, argv);

    hwloc_topology_t topology;

    // Runtime system status.
    hwloc_topology_init(&topology);
    hwloc_topology_load(topology);

    // Emulate memory writting by saving data into memory.
    const size_t buffer_size = 4ULL * 1024 * 1024 * 1024;
    void* dram_buffer = create_dram_buffer(buffer_size);

    if (!dram_buffer)
    {
        XBT_ERROR("unable to create write buffer. errno: %d, error: %s", errno, strerror(errno));
        hwloc_topology_destroy(topology);
        exit(EXIT_FAILURE);
    }

    // Create some test data
    char* test_data = (char*)malloc(buffer_size);
    memset(test_data, 0xAA, buffer_size);

    // Write to DRAM
    double write_start_timestamp_us = get_time_us();
    dram_write(dram_buffer, test_data, buffer_size);
    double write_end_timestamp_us = get_time_us();

    // Get data locality after writing.
    std::vector<int> nlaw = thread_numa_get(topology, (char *)dram_buffer, buffer_size);

    // Read back from DRAM
    char* read_back = (char*)malloc(buffer_size);

    double read_start_timestemp_us = get_time_us();
    dram_read(read_back, dram_buffer, buffer_size);
    double read_end_timestemp_us = get_time_us();

    // Verify data
    if (memcmp(test_data, read_back, buffer_size) != 0) {
        XBT_ERROR("Data mismatch after read-back.");
        free(read_back);
        free(test_data);
        free(dram_buffer);
        hwloc_topology_destroy(topology);
        exit(EXIT_FAILURE);
    }
    
    // Used to check data (pages) migration. Migration is trigered once the data is being read.
    std::vector<int> nlar = thread_numa_get(topology, (char *)dram_buffer, buffer_size);

    thread_locality_t locality = thread_get_locality_from_os(topology);
    XBT_INFO("numa_id: %d, code_id: %d, vcs: %ld, ics: %ld, mig: %ld, numa_write: [%s], numa_read: [%s], write_time_us: %f, read_time_us: %f, payload: %ld.",
        locality.numa_id, locality.core_id, locality.voluntary_context_switches, 
        locality.involuntary_context_switches, locality.core_migrations,
        join(nlaw).c_str(), join(nlar).c_str(),
        write_end_timestamp_us - write_start_timestamp_us,
        read_end_timestemp_us - read_start_timestemp_us,
        buffer_size
    );

    free(dram_buffer);
    free(test_data);
    free(read_back);

    hwloc_topology_destroy(topology);

    return 0;
}

double get_time_us()
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec * 1000000 + tv.tv_usec;
}

// Create an uncached buffer
void* create_dram_buffer(size_t size) {
    void* ptr;
    if (posix_memalign(&ptr, CACHE_LINE_SIZE, size) != 0) {
        return NULL;
    }
    memset(ptr, 0, size);
    return ptr;
}

// Non-temporal write (bypasses cache)
void dram_write(void* dest, const void* src, size_t size) {
    size_t i;
    char* d = (char*)dest;
    const char* s = (const char*)src;
    
    // Use non-temporal stores for large blocks
    #ifdef __AVX512F__
    for (i = 0; i + 64 <= size; i += 64) {
        __m512i val = _mm512_loadu_si512((__m512i*)(s + i));
        _mm512_stream_si512((__m512i*)(d + i), val);
    }
    #elif defined(__AVX__)
    for (i = 0; i + 32 <= size; i += 32) {
        __m256i val = _mm256_loadu_si256((__m256i*)(s + i));
        _mm256_stream_si256((__m256i*)(d + i), val);
    }
    #else
    for (i = 0; i + 16 <= size; i += 16) {
        __m128i val = _mm_loadu_si128((__m128i*)(s + i));
        _mm_stream_si128((__m128i*)(d + i), val);
    }
    #endif
    
    // Handle remaining bytes
    for (; i < size; i++) {
        d[i] = s[i];
    }
    
    _mm_sfence();
}

// Non-temporal read (bypasses cache)
void dram_read(void* dest, const void* src, size_t size) {
    size_t i;
    char* d = (char*)dest;
    const char* s = (const char*)src;
    
    // Use non-temporal loads for large blocks
    #ifdef __AVX512F__
    for (i = 0; i + 64 <= size; i += 64) {
        __m512i val = _mm512_stream_load_si512((__m512i*)(s + i));
        _mm512_storeu_si512((__m512i*)(d + i), val);
    }
    #elif defined(__AVX__)
    for (i = 0; i + 32 <= size; i += 32) {
        __m256i val = _mm256_stream_load_si256((__m256i*)(s + i));
        _mm256_storeu_si256((__m256i*)(d + i), val);
    }
    #else
    for (i = 0; i + 16 <= size; i += 16) {
        __m128i val = _mm_stream_load_si128((__m128i*)(s + i));
        _mm_storeu_si128((__m128i*)(d + i), val);
    }
    #endif
    
    // Handle remaining bytes
    for (; i < size; i++) {
        d[i] = s[i];
    }
    
    _mm_lfence();
}

std::string join(const std::vector<int> &vec, const std::string &delimiter)
{
    std::ostringstream oss;

    for (size_t i = 0; i < vec.size(); ++i)
    {
        oss << vec[i];
        if (i != vec.size() - 1)
        { // Avoid adding a delimiter after the last element
            oss << delimiter;
        }
    }

    return oss.str();
}

std::vector<int> thread_numa_get(hwloc_topology_t topology, char *address, size_t size)
{
    /* Get data locality (NUMA nodes were data pages are allocated) */
    hwloc_nodeset_t nodeset = hwloc_bitmap_alloc();
    std::vector<int> numa_nodes;

    if (hwloc_get_area_memlocation(topology, address, size, nodeset, HWLOC_MEMBIND_BYNODESET) != 0)
    {
        XBT_ERROR("failed to retrieve memory binding for address: %p", address);
        throw std::runtime_error(std::string("failed to retrieve memory binding for address: ") + address);    
    }

    int node;
    hwloc_bitmap_foreach_begin(node, nodeset)
    {
        numa_nodes.push_back(node); // Add NUMA node ID to the vector
    }
    hwloc_bitmap_foreach_end();

    // Cleanup
    hwloc_bitmap_free(nodeset);

    return numa_nodes;
}

thread_locality_t thread_get_locality_from_os(hwloc_topology_t topology)
{
    // Get the current thread's CPU binding
    hwloc_bitmap_t cpuset = hwloc_bitmap_alloc();
    hwloc_get_last_cpu_location(topology, cpuset, HWLOC_CPUBIND_THREAD);

    // Get the NUMA node on which the current thread is running
    hwloc_bitmap_t nodeset = hwloc_bitmap_alloc();
    hwloc_cpuset_to_nodeset(topology, cpuset, nodeset);

    int numa_id = hwloc_bitmap_first(nodeset); // Get the first NUMA node

    // Get the core object corresponding to the CPU binding
    hwloc_obj_t obj = hwloc_get_obj_covering_cpuset(topology, cpuset);

    // Cleanup
    hwloc_bitmap_free(cpuset);
    hwloc_bitmap_free(nodeset);

    // Traverse up the object hierarchy to find the core object
    while (obj && obj->type != HWLOC_OBJ_CORE) obj = obj->parent;

    if (!obj)
    {
        XBT_ERROR("failed to get core object.");
        throw std::runtime_error("failed to get core object.");
    }

    int core_id = obj->logical_index; // Get the logical core ID

    // Retrieve core migration information from /proc/self/sched
    std::ifstream sched_file("/proc/self/sched");

    if (!sched_file.is_open()) {
        XBT_ERROR("failed to open /proc/self/sched: %s", strerror(errno));
        throw std::runtime_error("failed to open process scheduling information.");
    }

    std::string line;
    int core_migrations;
    while (std::getline(sched_file, line))
    {
        if (line.find("nr_migrations") != std::string::npos)
        {
            std::istringstream iss(line);
            std::string label;
            iss >> label >> core_migrations; // Extract migration count
            break;
        }
    }
    sched_file.close();

    // Get context switch information using getrusage
    struct rusage usage;
    getrusage(RUSAGE_THREAD, &usage);

    // Return locality and context switch information along with core migrations
    return {numa_id, core_id, usage.ru_nvcsw, usage.ru_nivcsw, core_migrations};
}

