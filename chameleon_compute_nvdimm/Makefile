#==============================
#    Evaluation Logic
#==============================

# Runtime logging configuration
# RUNTIME_LOG_FLAGS := \
# 	--log=fifo_scheduler.thres:debug \
# 	--log=heft_scheduler.thres:debug \
# 	--log=eft_scheduler.thres:debug \
# 	--log=hardware.thres:debug
EXECUTABLE := ../bin/nflows $(RUNTIME_LOG_FLAGS)

# Directories and Executables
SCRIPTS_DIR := ../scripts
PYTHON_EXEC := $(SCRIPTS_DIR)/.env/bin/python3
SLURM_EXEC := /bin/sbatch --cpus-per-task=$(shell nproc)
PBS_EXEC := /bin/qsub

# Validation Scripts
VALIDATE_OFFSETS := $(PYTHON_EXEC) $(SCRIPTS_DIR)/validate_offsets.py
VALIDATE_OUTPUT := $(PYTHON_EXEC) $(SCRIPTS_DIR)/validate_output.py

# Configuration Generation Scripts
GENERATE_CONFIG := $(PYTHON_EXEC) $(SCRIPTS_DIR)/generate_config.py
GENERATE_SLURM := $(PYTHON_EXEC) $(SCRIPTS_DIR)/generate_slurm.py
GENERATE_PBS := $(PYTHON_EXEC) $(SCRIPTS_DIR)/generate_pbs.py

# Visualization and Reporting Scripts
GENERATE_GANTT := $(PYTHON_EXEC) $(SCRIPTS_DIR)/generate_gantt.py
GENERATE_PROFILE := $(PYTHON_EXEC) $(SCRIPTS_DIR)/generate_profile.py

# Data Aggregation and Plotting Scripts
GENERATE_AGGREG := $(PYTHON_EXEC) $(SCRIPTS_DIR)/generate_aggreg.py
GENERATE_AGGREG_PLOT := $(PYTHON_EXEC) $(SCRIPTS_DIR)/generate_aggreg_plot_v3.0.py

EVALUATION_DIR := .
EVALUATION_TEMPLATE_DIR := $(EVALUATION_DIR)/templates
EVALUATION_WORKFLOW_DIR := $(EVALUATION_DIR)/workflows

EVALUATION_RESULT_DIR := $(EVALUATION_DIR)/results
EVALUATION_LOG_DIR := $(EVALUATION_RESULT_DIR)/log
EVALUATION_OUTPUT_DIR := $(EVALUATION_RESULT_DIR)/output
EVALUATION_CONFIG_DIR := $(EVALUATION_RESULT_DIR)/config
EVALUATION_SLURM_DIR := $(EVALUATION_RESULT_DIR)/slurm
EVALUATION_PBS_DIR := $(EVALUATION_RESULT_DIR)/pbs

EVALUATION_SLEEPTIME := 10
EVALUATION_REPEATS := 5
EVALUATION_GROUPS := $(notdir $(shell find $(EVALUATION_TEMPLATE_DIR) -mindepth 1 -maxdepth 1 -type d))
EVALUATION_WORKFLOWS := $(notdir $(shell find $(EVALUATION_WORKFLOW_DIR) -mindepth 1 -maxdepth 1 -type f -name "*.dot" 2>/dev/null))
EVALUATION_CONFIG_DIRS :=  $(notdir $(shell find $(EVALUATION_CONFIG_DIR) -mindepth 1 -maxdepth 1 -type d 2>/dev/null))

BACKUP_DIR := ../backups
BACKUP_DIRS := $(EVALUATION_DIR)
CLEAN_PATHS :=$(EVALUATION_RESULT_DIR)

all: backup

print-%:
	@echo '$*=$($*)'

.PHONY: backup
backup:
	@mkdir -p $(BACKUP_DIR)
	@BASE_NAME=$(shell date +"%Y%m%d_%H%M%S"); \
	BACKUP_FILE=$(BACKUP_DIR)/$${BASE_NAME}.zip; \
	LOG_FILE=$(BACKUP_DIR)/$${BASE_NAME}.log; \
	if zip -r $$BACKUP_FILE $(BACKUP_DIRS) > $$LOG_FILE 2>&1; then \
		echo "Backup saved to $$BACKUP_FILE"; \
	else \
		echo "Backup failed"; \
	fi

.PHONY: clean
clean: backup
	@for dir in $(CLEAN_PATHS); do \
		echo "Cleaning $$dir";\
		[ -d $$dir ] && rm -rf $$dir/* && find $$dir -type d -empty -exec rmdir {} + || true; \
	done

# Rule: sentinel file depends on input DOT file
.PRECIOUS: $(EVALUATION_CONFIG_DIR)/%/.generated
$(EVALUATION_CONFIG_DIR)/%/.generated: $(EVALUATION_WORKFLOW_DIR)/%.dot
	@echo "[INFO] Generating configs for workflow: $*"
	@for group in $(EVALUATION_GROUPS); do \
		for json_template in $$(ls $(EVALUATION_TEMPLATE_DIR)/$$group/*.json 2>/dev/null); do \
			BASE_NAME=$$(basename $$json_template .json); \
			CONFIG_DIR=$(EVALUATION_CONFIG_DIR)/$*/$$group/$$BASE_NAME; \
			OUTPUT_DIR=$(EVALUATION_OUTPUT_DIR)/$*/$$group/$$BASE_NAME; \
			LOG_DIR=$(EVALUATION_LOG_DIR)/$*; \
			mkdir -p $$CONFIG_DIR $$OUTPUT_DIR $$LOG_DIR; \
			CONFIG_FILE=$$CONFIG_DIR/config.json; \
			OUTPUT_FILE=$$OUTPUT_DIR/output.yaml; \
			LOG_FILE=$$LOG_DIR/workflow.log; \
			$(GENERATE_CONFIG) \
				--template "$$json_template" \
				--output_file "$$CONFIG_FILE" \
				--params out_file_name="$$OUTPUT_FILE" dag_file="$(EVALUATION_WORKFLOW_DIR)/$*.dot" \
				>> "$$LOG_FILE" 2>&1; \
			GENERATE_STATUS=$$?; \
			if [ $$GENERATE_STATUS -eq 0 ]; then \
				printf "  [SUCCESS] $$CONFIG_FILE\n"; \
			else \
				printf "  [FAILED] $$CONFIG_FILE (Generate: $$GENERATE_STATUS)\n"; \
			fi; \
			sleep $(EVALUATION_SLEEPTIME); \
		done; \
	done
	@touch $@ # Create the sentinel file to indicate completion

%.json: $(EVALUATION_CONFIG_DIR)/%/.generated
	@true # This rule is a placeholder to ensure the directory exists

%.yaml: %.json
	@echo "[INFO] Running workflow executions for: $*"
	@CONFIG_DIR=$(EVALUATION_CONFIG_DIR)/$*; \
	find $$CONFIG_DIR -name config.json | while read -r CONFIG_FILE; do \
		for repeat in $(shell seq 1 $(EVALUATION_REPEATS)); do \
			LOG_FILE=$$(echo "$$CONFIG_FILE" | sed 's|/config/|/log/|' | sed 's|config.json|'"$$repeat"'.log|'); \
			SRC_FILE=$$(echo "$$CONFIG_FILE" | sed 's|/config/|/output/|' | sed 's|config.json|output.yaml|'); \
			DST_FILE=$$(echo "$$CONFIG_FILE" | sed 's|/config/|/output/|' | sed 's|config.json|'"$$repeat"'.yaml|'); \
			mkdir -p "$$(dirname $$LOG_FILE)"; \
			START_TIME=$$(date +%s.%N); \
			$(EXECUTABLE) "$${CONFIG_FILE}" >  "$$LOG_FILE" 2>&1; \
			EXECUTABLE_STATUS=$$?; \
			END_TIME=$$(date +%s.%N); \
			ELAPSED_TIME_SEC=$$(echo "$$END_TIME - $$START_TIME" | bc); \
			mv $$SRC_FILE $$DST_FILE; \
			printf "Execution time: %.3f s\n" "$$ELAPSED_TIME_SEC" >> "$$LOG_FILE"; \
			$(VALIDATE_OFFSETS) "$${DST_FILE}"  >> "$$LOG_FILE" 2>&1; \
			VALIDATE_STATUS=$$?; \
			if [ $$EXECUTABLE_STATUS -eq 0 ] && [ $$VALIDATE_STATUS -eq 0 ]; then \
				printf "  [SUCCESS] $$CONFIG_FILE (Time: %.3f s)\n" "$$ELAPSED_TIME_SEC"; \
			else \
				printf "  [FAILED] $$CONFIG_FILE (Execute: $$EXECUTABLE_STATUS, Validate: $$VALIDATE_STATUS, Time: %.3f s)\n" "$$ELAPSED_TIME_SEC"; \
			fi; \
			sleep $(EVALUATION_SLEEPTIME); \
		done; \
	done

.PHONY: all-yamls
all-yamls: $(addsuffix .yaml, $(basename $(EVALUATION_WORKFLOWS)))

# Slurm Job Generation and Submission

.PRECIOUS: $(EVALUATION_SLURM_DIR)/%.slurm
$(EVALUATION_SLURM_DIR)/%.slurm: $(EVALUATION_CONFIG_DIR)/%/.generated
	@echo "[INFO] Generating SLURM job for: $*"
	@mkdir -p "$(EVALUATION_SLURM_DIR)"
	@CONFIG_DIR=$(EVALUATION_CONFIG_DIR)/$*; \
	WORKFLOW_LOG_FILE=$(EVALUATION_LOG_DIR)/$*/workflow.log; \
	find $$CONFIG_DIR -name config.json | while read -r CONFIG_FILE; do \
		SLURM_FILE=$$(echo "$$CONFIG_FILE" | sed 's|/config/|/slurm/|' | sed 's|config.json|submit.sbatch|'); \
		LOG_DIR=$$(echo "$$CONFIG_FILE" | sed 's|/config/|/log/|' | sed 's|config.json||'); \
		mkdir -p "$$LOG_DIR"; \
		$(GENERATE_SLURM) --job "$*" \
			--config_file "$$CONFIG_FILE" \
			--execute_command "$(EXECUTABLE) $${CONFIG_FILE}" \
			--validate_command "$(VALIDATE_OFFSETS)" \
			--repeats $(EVALUATION_REPEATS) \
			--log_dir "$$LOG_DIR" \
			--output "$$SLURM_FILE" >> "$$WORKFLOW_LOG_FILE" 2>&1; \
		GENERATE_STATUS=$$?; \
		chmod +x "$$SLURM_FILE"; \
		if [ $$GENERATE_STATUS -eq 0 ]; then \
			printf "  [SUCCESS] $$SLURM_FILE\n"; \
		else \
			printf "  [FAILED] $$SLURM_FILE (Generate: $$GENERATE_STATUS)\n"; \
		fi; \
	done
	@touch $@ # Create the sentinel file to indicate completion

# Redirect target (so `make NAME.slurm` works)
%.slurm: $(EVALUATION_SLURM_DIR)/%.slurm
	@true

.PRECIOUS: $(EVALUATION_SLURM_DIR)/%.submitted
$(EVALUATION_SLURM_DIR)/%.submitted: $(EVALUATION_SLURM_DIR)/%.slurm
	@echo "[INFO] Submitting workflow: $*"
	@SLURM_DIR=$(EVALUATION_SLURM_DIR)/$*; \
	WORKFLOW_LOG_FILE=$(EVALUATION_LOG_DIR)/$*/workflow.log; \
	find $$SLURM_DIR -name submit.sbatch | while read -r SLURM_FILE; do \
		$(SLURM_EXEC) "$$SLURM_FILE" >> "$$WORKFLOW_LOG_FILE" 2>&1; \
		SLURM_STATUS=$$?; \
		if [ $$SLURM_STATUS -eq 0 ]; then \
			printf "  [SUCCESS] $$SLURM_FILE\n"; \
		else \
			printf "  [FAILED] $$SLURM_FILE (Generate: $$SLURM_STATUS)\n"; \
		fi; \
	done
	@touch $@ # Create the sentinel file to indicate completion

# Redirect target (so `make NAME.slurm` works)
%.submit_slurm: $(EVALUATION_SLURM_DIR)/%.submitted
	@true

# PBS Job Generation and Submission

.PRECIOUS: $(EVALUATION_PBS_DIR)/%.pbs
$(EVALUATION_PBS_DIR)/%.pbs: $(EVALUATION_CONFIG_DIR)/%/.generated
	@echo "[INFO] Generating PBS job for: $*"
	@mkdir -p "$(EVALUATION_PBS_DIR)"
	@CONFIG_DIR=$(EVALUATION_CONFIG_DIR)/$*; \
	WORKFLOW_LOG_FILE=$(EVALUATION_LOG_DIR)/$*/workflow.log; \
	find $$CONFIG_DIR -name config.json | while read -r CONFIG_FILE; do \
		PBS_FILE=$$(echo "$$CONFIG_FILE" | sed 's|/config/|/pbs/|' | sed 's|config.json|submit.sbatch|'); \
		LOG_DIR=$$(echo "$$CONFIG_FILE" | sed 's|/config/|/log/|' | sed 's|config.json||'); \
		mkdir -p "$$LOG_DIR"; \
		$(GENERATE_PBS) --job "$*" \
			--config_file "$$CONFIG_FILE" \
			--execute_command "$(EXECUTABLE) $${CONFIG_FILE}" \
			--validate_command "$(VALIDATE_OFFSETS)" \
			--repeats $(EVALUATION_REPEATS) \
			--log_dir "$$LOG_DIR" \
			--output "$$PBS_FILE" >> "$$WORKFLOW_LOG_FILE" 2>&1; \
		GENERATE_STATUS=$$?; \
		chmod +x "$$PBS_FILE"; \
		if [ $$GENERATE_STATUS -eq 0 ]; then \
			printf "  [SUCCESS] $$PBS_FILE\n"; \
		else \
			printf "  [FAILED] $$PBS_FILE (Generate: $$GENERATE_STATUS)\n"; \
		fi; \
	done
	@touch $@ # Create the sentinel file to indicate completion

# Redirect target (so `make NAME.pbs` works)
%.pbs: $(EVALUATION_PBS_DIR)/%.pbs
	@true

.PRECIOUS: $(EVALUATION_PBS_DIR)/%.submitted
$(EVALUATION_PBS_DIR)/%.submitted: $(EVALUATION_PBS_DIR)/%.pbs
	@echo "[INFO] Submitting workflow: $*"
	@PBS_DIR=$(EVALUATION_PBS_DIR)/$*; \
	WORKFLOW_LOG_FILE=$(EVALUATION_LOG_DIR)/$*/workflow.log; \
	find $$PBS_DIR -name submit.sbatch | while read -r PBS_FILE; do \
		$(PBS_EXEC) "$$PBS_FILE" >> "$$WORKFLOW_LOG_FILE" 2>&1; \
		PBS_STATUS=$$?; \
		if [ $$PBS_STATUS -eq 0 ]; then \
			printf "  [SUCCESS] $$PBS_FILE\n"; \
		else \
			printf "  [FAILED] $$PBS_FILE (Generate: $$PBS_STATUS)\n"; \
		fi; \
	done
	@touch $@ # Create the sentinel file to indicate completion

# Redirect target (so `make NAME.slurm` works)
%.submit_pbs: $(EVALUATION_PBS_DIR)/%.submitted
	@true
