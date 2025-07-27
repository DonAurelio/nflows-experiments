#!/bin/bash

# Check that a directory was provided
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/search"
  exit 1
fi

# Get the absolute path of the base directory
BASE_DIR="$1"

# Find all .out files and print full path and contents
find "$BASE_DIR" -type f -name "*.out" | while read -r file; do
  echo "=== FILE: $file ==="
  cat "$file"
  echo
done
