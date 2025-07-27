#include <hwloc.h>
#include <sys/time.h>
#include <xbt/log.h>
#include <vector>
#include <sstream>
#include <sys/resource.h> // For getrusage
#include <fstream>
#include <x86intrin.h> // For _mm_stream_si64, _mm_clflush
#include <iostream>

XBT_LOG_NEW_DEFAULT_CATEGORY(example, "example");

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

void* aligned_alloc(size_t size, size_t alignment);
void dram_write(char* ptr, size_t size, char value);
void dram_read(char* ptr, size_t size);

std::string join(const std::vector<int> &vec, const std::string &delimiter=",");
std::vector<int> thread_numa_get(hwloc_topology_t topology, char *address, size_t size);
thread_locality_t thread_get_locality_from_os(hwloc_topology_t topology);

int main(int argc, char *argv[])
{
    // Initialize XBT logging system
    xbt_log_init(&argc, argv);

    size_t payload_bytes = 4ULL * 1024 * 1024 * 1024;

    hwloc_topology_t topology;

    // Runtime system status.
    hwloc_topology_init(&topology);
    hwloc_topology_load(topology);

    // Emulate memory writting by saving data into memory.
    char* buffer = static_cast<char*>(aligned_alloc(payload_bytes, 64));
    if (!buffer)
    {
        XBT_ERROR("unable to create write buffer. errno: %d, error: %s", errno, strerror(errno));
        hwloc_topology_destroy(topology);
        exit(EXIT_FAILURE);
    }

    // Emulate memory writting by saving data into memory.
    double write_start_timestamp_us = get_time_us();

    dram_write(buffer, payload_bytes, 0x00);  // Write 0x00 to DRAM

    double write_end_timestamp_us = get_time_us();

    // Get data locality after writing.
    std::vector<int> nlaw = thread_numa_get(topology, buffer, payload_bytes);

    double read_start_timestemp_us = get_time_us();

    dram_read(buffer, payload_bytes);

    double read_end_timestemp_us = get_time_us();

    // Used to check data (pages) migration. Migration is trigered once the data is being read.
    std::vector<int> nlar = thread_numa_get(topology, buffer, payload_bytes);

    thread_locality_t locality = thread_get_locality_from_os(topology);
    XBT_INFO("numa_id: %d, code_id: %d, vcs: %ld, ics: %ld, mig: %ld, numa_write: [%s], numa_read: [%s], write_time_us: %f, read_time_us: %f, payload: %ld.",
        locality.numa_id, locality.core_id, locality.voluntary_context_switches, 
        locality.involuntary_context_switches, locality.core_migrations,
        join(nlaw).c_str(), join(nlar).c_str(),
        write_end_timestamp_us - write_start_timestamp_us,
        read_end_timestemp_us - read_start_timestemp_us,
        payload_bytes
    );

    free(buffer);

    hwloc_topology_destroy(topology);

    return 0;
}

double get_time_us()
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec * 1000000 + tv.tv_usec;
}

// Aligned allocation (64-byte alignment for streaming stores)
void* aligned_alloc(size_t size, size_t alignment)
{
    void* ptr;
    if (posix_memalign(&ptr, alignment, size) != 0) {
        std::cerr << "Failed to allocate aligned memory\n";
        return nullptr;
    }
    return ptr;
}

// Fill memory with non-temporal stores (bypass cache)
void dram_write(char* ptr, size_t size, char value)
{
    // Reinterpret as 64-bit blocks for _mm_stream_si64
    constexpr size_t stride = 8; // 8 bytes per write
    for (size_t i = 0; i < size; i += stride) {
        // Broadcast 'value' to 64 bits and store non-temporally
        long long pattern = static_cast<long long>(value) * 0x0101010101010101LL;
        _mm_stream_si64(reinterpret_cast<long long*>(ptr + i), pattern);
    }
    _mm_sfence();  // Ensure writes complete
}

// Read memory while flushing cache to force DRAM access
void dram_read(char* ptr, size_t size) {
    volatile char dummy;
    for (size_t i = 0; i < size; i += 64) {
        dummy = ptr[i];               // Read
        _mm_clflush(ptr + i);         // Flush cache line immediately
    }
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

