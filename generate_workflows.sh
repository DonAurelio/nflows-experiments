#!/bin/bash

# Usage:
# ./generate_workflows.sh <input_json_folder> <output_folder>

# Check for required arguments
if [ $# -ne 2 ]; then
  echo "Usage: $0 <input_json_folder> <output_folder>"
  exit 1
fi

INPUT_FOLDER="$1"
OUTPUT_FOLDER="$2"
WORKFLOW_LIST="$OUTPUT_FOLDER/workflow_list.txt"

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_FOLDER"

# Collect all .json files recursively and convert to workflow names (relative paths, no extension)
ALL_WORKFLOWS=()
while IFS= read -r -d '' json_file; do
  relative_path="${json_file#$INPUT_FOLDER/}"
  workflow_name="${relative_path%.json}"
  ALL_WORKFLOWS+=( "$workflow_name" )
done < <(find "$INPUT_FOLDER" -type f -name "*.json" -print0)

# Determine the list of workflows to process
if [ -f "$WORKFLOW_LIST" ]; then
  echo "Using workflow list from $WORKFLOW_LIST"
  mapfile -t REQUESTED_WORKFLOWS < "$WORKFLOW_LIST"
  WORKFLOWS=()

  # Filter the found workflows by the requested ones
  for requested in "${REQUESTED_WORKFLOWS[@]}"; do
    for wf in "${ALL_WORKFLOWS[@]}"; do
      if [[ "$wf" == *"$requested"* ]]; then
        WORKFLOWS+=( "$wf" )
        break
      fi
    done
  done
else
  echo "No workflow list found, using all discovered workflows."
  WORKFLOWS=("${ALL_WORKFLOWS[@]}")
fi

# Iterate and generate workflows
for workflow_name in "${WORKFLOWS[@]}"; do
  json_file="$INPUT_FOLDER/${workflow_name}.json"

  if [ ! -f "$json_file" ]; then
    echo "Warning: File '$json_file' not found. Skipping."
    continue
  fi

  base_name=$(basename "$workflow_name")

  dot_C="$OUTPUT_FOLDER/C_${base_name}.dot"
  dot_S="$OUTPUT_FOLDER/S_${base_name}.dot"
  dot_L="$OUTPUT_FOLDER/L_${base_name}.dot"

  nflows_generate_dot "$json_file" "$dot_C" --dep_constant 40000000 --flops_constant 10000000
  nflows_generate_dot "$json_file" "$dot_S" --dep_scale_range 4e7 5e7 --flops_constant 10000000
  nflows_generate_dot "$json_file" "$dot_L" --dep_scale_range 4e7 1e8 --flops_constant 10000000
done

echo "Workflows generated in $OUTPUT_FOLDER"
