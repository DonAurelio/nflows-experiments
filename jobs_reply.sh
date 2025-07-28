#!/bin/bash

input_file="$1"

for file in $(cat "$input_file"); do
    /bin/sbatch --cpus-per-task=$(nproc) "$file"
done
