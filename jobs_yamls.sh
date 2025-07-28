#!/bin/bash

# Usage: ./jobs_output_summary.sh /path/to/output

ROOT="${1:-.}"  # Use current directory if not specified

find "$ROOT" -type d | while read -r dir; do
    # Count the number of subdirectories inside this directory
    subdirs=$(find "$dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
    
    if [ "$subdirs" -eq 0 ]; then
        # It's a leaf folder; count .yaml and .yml files
        yaml_count=$(find "$dir" -maxdepth 1 -type f \( -iname "*.yaml" -o -iname "*.yml" \) | wc -l)
        echo "$dir: $yaml_count"
    fi
done
