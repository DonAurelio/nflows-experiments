#!/bin/bash

# Check that a directory was provided
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/search"
  exit 1
fi

# Get the absolute path of the base directory
BASE_DIR="$1"

# Print CSV header
echo "experiment;algorithm;level;time"

#!/bin/bash

# Print CSV header
echo "experiment,algorithm,level,time,yaml_size_kb"

# Find all .out files and process them
find "$BASE_DIR" -type f -name "*.out" | while read -r file; do
  grep "\[SUCCESS\]" "$file" | while read -r line; do
    if [[ "$line" =~ \[SUCCESS\]\ \.\/results/config/([^/]+)/([^/]+)/([^/]+)/config\.json\ \(Time:\ ([0-9.]+)\ s\) ]]; then
      experiment="${BASH_REMATCH[1]}"
      algorithm="${BASH_REMATCH[2]}"
      level="${BASH_REMATCH[3]}"
      time="${BASH_REMATCH[4]}"
      
      # Look for the first .yaml file in the specified output path
      yaml_dir="$BASE_DIR/../output/$experiment/$algorithm/$level/"
      yaml_file=$(find "$yaml_dir" -maxdepth 1 -type f -name "*.yaml" | sort | head -n 1)
      
      # Get YAML file size in kilobytes (rounded to 2 decimal places)
      if [ -f "$yaml_file" ]; then
        size_bytes=$(stat -c%s "$yaml_file")
        size_kb=$(awk "BEGIN { printf \"%.2f\", $size_bytes/1024 }")
      else
        size_kb="0.00"
      fi

      echo "$experiment;$algorithm;$level;$time;$size_kb"
    fi
  done
done
