# NUMA Balancing and Hardware Prefetchers Control Scripts

This repository includes two scripts:

* `set_numa_balancing.sh`: Enables, disables, or checks the status of Linux NUMA balancing.
* `set_prefetchers.sh`: Enables, disables, or checks the status of Intel hardware prefetchers via MSRs.

## Requirements

### For `set_prefetchers.sh`:

- `msr-tools` must be **installed**:

    ```bash
    sudo apt install msr-tools
    ```

- Load the `msr` kernel module:

    ```bash
    sudo modprobe msr
    ```

- Must be executed with `sudo`. 

## Usage

### `set_prefetchers.sh`

```sh
sudo ./set_prefetchers.sh disable all   # Disable all prefetchers
sudo ./set_prefetchers.sh enable all    # Enable all prefetchers
sudo ./set_prefetchers.sh disable 0x5   # Disable specific prefetchers using bitmask
sudo ./set_prefetchers.sh enable 0x0    # Enable all prefetchers (reset bitmask)
sudo ./set_prefetchers.sh status        # Show current status
```

This script writes to MSR 0x1A4 (per core). Bitmask format:

| Bit | Prefetcher                              |
| --- | --------------------------------------- |
| 0   | L2 Hardware Prefetcher                  |
| 1   | L2 Adjacent Cache Line Prefetcher       |
| 2   | DCU (L1) Streamer Prefetcher            |
| 3   | DCU Instruction Pointer (IP) Prefetcher |

In NUMA systems, read prefetchers often mask the latency gap between local and remote memory accesses by preloading data into cache. As a result, read performance appears similar regardless of the memory's physical location. However, when prefetchers are disabled, the system exhibits the actual disparity between local and remote read latencies.

The following steps illustrate how to compile and run a test to measure data access performance:

```sh
source ./simgrid_source.sh
g++ 1_base_line.cpp -lhwloc -lsimgrid
```

#### With Prefetchers Enabled

When prefetchers are enabled, note that the `read_time_us` values for local and remote memory accesses are nearly equivalent:

```sh
numactl --cpubind=0 --membind=0 ./a.out
[0.000000] [example/INFO] numa_id: 0, code_id: 16, vcs: 2, ics: 247, mig: 0, checksum: 0, numa_write: [0], numa_read: [0], write_time_us: 1959836.000000, read_time_us: 9368193.000000, payload: 4000000000.

numactl --cpubind=0 --membind=3 ./a.out
[0.000000] [example/INFO] numa_id: 0, code_id: 17, vcs: 2, ics: 246, mig: 0, checksum: 0, numa_write: [3], numa_read: [3], write_time_us: 3139211.000000, read_time_us: 9384338.000000, payload: 4000000000.
```

#### With Prefetchers Disabled

When prefetchers are disabled, the `read_time_us` values show a clear difference between local and remote memory accesses:

```sh
numactl --cpubind=0 --membind=0 ./a.out
[0.000000] [example/INFO] numa_id: 0, code_id: 18, vcs: 2, ics: 243, mig: 0, checksum: 0, numa_write: [0], numa_read: [0], write_time_us: 1976835.000000, read_time_us: 13473153.000000, payload: 4000000000.

numactl --cpubind=0 --membind=3 ./a.out
[0.000000] [example/INFO] numa_id: 0, code_id: 19, vcs: 2, ics: 253, mig: 0, checksum: 0, numa_write: [3], numa_read: [3], write_time_us: 3167309.000000, read_time_us: 17367098.000000, payload: 4000000000.
```

### `set_numa_balancing.sh`

```sh
sudo ./numa_balancing.sh enable
sudo ./numa_balancing.sh disable
./numa_balancing.sh status
```
