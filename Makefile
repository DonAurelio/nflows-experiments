#==============================
#    Evaluation Logic
#==============================

# RUNTIME_LOG_FLAGS := \
# 	--log=fifo_scheduler.thres:debug \
# 	--log=heft_scheduler.thres:debug \
# 	--log=eft_scheduler.thres:debug \
# 	--log=hardware.thres:debug
NFLOWS_EXE := nflows $(RUNTIME_LOG_FLAGS)
SLURM_EXE := /bin/sbatch --cpus-per-task=$(shell nproc)
SLURM_JOB_TIMEOUT := 01:00:00

# Configuration Generation Scripts
GENERATE_CONFIG := nflows_generate_config
GENERATE_SLURM := nflows_generate_slurm

EVALUATION_DIR := .
EVALUATION_TEMPLATE_DIR := $(EVALUATION_DIR)/templates
EVALUATION_WORKFLOW_DIR := $(EVALUATION_DIR)/workflows

EVALUATION_RESULT_DIR := $(EVALUATION_DIR)/results
EVALUATION_LOG_DIR := $(EVALUATION_RESULT_DIR)/log
EVALUATION_OUTPUT_DIR := $(EVALUATION_RESULT_DIR)/output
EVALUATION_CONFIG_DIR := $(EVALUATION_RESULT_DIR)/config
EVALUATION_SLURM_DIR := $(EVALUATION_RESULT_DIR)/slurm

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
			--time_limit "$(SLURM_JOB_TIMEOUT)" \
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
%.submit: $(EVALUATION_SLURM_DIR)/%.submitted
	@true
