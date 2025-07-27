<img src="https://raw.githubusercontent.com/DonAurelio/nflows/refs/heads/main/logo.png"
     align="right"
     width="15%"
     alt="nFlows logo\">

# nFlows: Experiments

Provides the complete setup and automation scripts for running reproducible experiments when implementing NUMA-aware scheduling algorithms in [nflows](https://github.com/DonAurelio/nflows).

### Requirements

1. **OS:** Ubuntu 22.04
2. **Software:** [nflows-tools](https://github.com/DonAurelio/nflows-tools)

### Experiments

1. `chameleon_cascade_lake_r`: Performance evaluation of three NUMA-aware scheduling algorithms (fifo, heft, min-min) on a system with two NUMA domains.
2. `chameleon_compute_nvdimm`: Performance evaluation of three NUMA-aware scheduling algorithms (fifo, heft, min-min) on a system with four NUMA domains.

## Usage

1. Select and experiment, e.g., `chameleon_cascade_lake_r`.
2. Generate the workflows to be used in the experiment.

     ```sh
     ./generate_workflows.sh ./workflows ./chameleon_cascade_lake_r/workflows
     ```
     
     The command searches for `workflow_list.txt` in `./chameleon_cascade_lake_r/workflows` and generates the DOT files required by [nFlows](https://github.com/DonAurelio/nflows) for the specified workflows in the experiment.

3. Validate the list of workflows generated for the experiment.

     ```sh
     make -C chameleon_cascade_lake_r print-EVALUATION_WORKFLOWS
     ```

4. Adjust [Makefile](./Makefile) to reflect the number of times each workflow should be executed (to compute averages or reduce the impact of outliers).

     ```sh
     EVALUATION_REPEATS := 1
     SLURM_JOB_TIMEOUT := 01:00:00
     ```

5. **[Option 1]** Execute one or more of the preconfigured workflows. Each workflow will be executed `EVALUATION_REPEATS` times for every experimental configuration defined in `./<experiment_folder>/templates/`. The name of the workflow must end with `.yaml`. This triggers the execution of the workflow and generates the runtime system output.

     ```sh
     make C_montage-chameleon-2mass-01d-001.yaml
     ```

7. **[Option 2]** generate a slurm submission file for the Slurm Workload Manager System. The name of the workflow must end with `.slurm`.

     ```sh
     make C_montage-chameleon-2mass-01d-001.slurm
     ```

     The system will create a single submission file per experimental configuration file defined in `./<experiment_folder>/templates/`.

     ```sh 
     [INFO] Generating SLURM job for: S_montage-chameleon-2mass-015d-001
       [SUCCESS] ./results/slurm/S_montage-chameleon-2mass-015d-001/fifo_8/1_M_1/submit.sbatch
     ```

8. **[Option 3]** Submit the workflow experiment directly to the Slurm Workload Manager. The workflow name must end with `.submit`.

     ```sh
     make C_montage-chameleon-2mass-01d-001.submit
     ```

9. Results will be stored in a newly created `results` folder. This folder will include the configuration files generated from [./evaluation/templates/](./evaluation/templates/), the log files (`.log`) produced during each repetition, the output files (`.yaml`) for each repetition, and the Slurm submission file if Option 2 is selected.

     ```sh
     results/
     ├── config
     │   └── S_montage-chameleon-2mass-015d-001
     │       └── fifo_8
     │           └── 1_M_1
     │               └── config.json
     ├── log
     │   └── S_montage-chameleon-2mass-015d-001
     │       ├── fifo_8
     │       │   └── 1_M_1
     │       │       └── 1.log
     │       └── log.txt
     ├── output
     │   └── S_montage-chameleon-2mass-015d-001
     │       └── fifo_8
     │           └── 1_M_1
     │               └── 1.yaml
     └── slurm
         ├── S_montage-chameleon-2mass-015d-001
         │   └── fifo_8
         │       └── 1_M_1
         │           └── submit.sbatch
         └── S_montage-chameleon-2mass-015d-001.slurm
     ```

## Anatomy of an Experiment

Every experiment folder contains three subfolders: System, Templates, and Workflows.

* The `system` folder includes the distance matrices of the NUMA-capable system under evaluation.
* The `templates` folder contains configuration file templates used to describe the experimental setup.
* The `workflows` folder contains all the input workflows considered for evaluation.

### System

Contains three configuration files:

1. Bandwidth distance matrix (values in GB/s). Examples: `non_uniform_bw.txt`, `uniform_bw.txt`.
2. Latency distance matrix (values in nanoseconds). Examples: `non_uniform_lat.txt`, `uniform_lat.txt`.
3. Relative distances among NUMA domains (dimensionless) [Optional]. Example: `non_uniform_lat_rel.txt`.

Values in these configuration files are made available to scheduling algorithms through the runtime API.
This enables the scheduler to make NUMA-aware scheduling decisions. In parallel, the runtime system retrieves memory and core locality information via the `hwloc` library. This information is also made accessible to scheduling algorithms at runtime.

### Templates

Contains experimental configuration files grouped into folders. These groups determine how the results will be organized. Each workflow is evaluated against all experimental configurations defined in the templates folder. A new configuration is automatically created by varying the `dag_file` and `out_file_name` fields in the configuration file when the workflow is executed.

```sh
templates
├── fifo_16
│   ├── 1_MA_1.json
│   ├── 1_M_1.json
│   ├── 1_SL_1.json
│   └── 1_SR_1.json
├── fifo_8
│   ├── 1_MA_1.json
│   ├── 1_M_1.json
│   ├── 1_SL_1.json
│   └── 1_SR_1.json
├── heft_16
│   ├── 1_MA_1.json
│   ├── 1_M_1.json
│   ├── 1_SL_1.json
│   └── 1_SR_1.json
├── heft_8
│   ├── 1_MA_1.json
│   ├── 1_M_1.json
│   ├── 1_SL_1.json
│   └── 1_SR_1.json
├── min_min_16
│   ├── 1_MA_1.json
│   ├── 1_M_1.json
│   ├── 1_SL_1.json
│   └── 1_SR_1.json
└── min_min_8
    ├── 1_MA_1.json
    ├── 1_M_1.json
    ├── 1_SL_1.json
    └── 1_SR_1.json
```

### Workflows 

Contains the workflows used for evaluation. The workflows were downloaded from the [WfInstances browser](https://wfinstances.ics.hawaii.edu/). Since the workflow traces were provided in JSON format, the [nflows_generate_dot](https://github.com/DonAurelio/nflows-tools) script was used to generate the DOT input files required by the runtime system. To handle parallel dependencies between tasks sharing multiple files, the script consolidates data items with identical filenames between parent outputs and child inputs.
