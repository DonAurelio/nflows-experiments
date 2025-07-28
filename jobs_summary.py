#!/usr/bin/env python3
import sys
import pandas as pd

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <input_file.csv>")
    sys.exit(1)

input_file = sys.argv[1]

# Load CSV
df = pd.read_csv(input_file, sep=";")

# Extract S/L/C from beginning of experiment and remove it
df['csl'] = df['experiment'].str.extract(r'^([SLC])_')
df['experiment'] = df['experiment'].str.replace(r'^[SLC]_', '', regex=True)

# Extract core count from algorithm and remove it
df['cores'] = df['algorithm'].str.extract(r'_([0-9]+)$').astype('Int64')
df['algorithm'] = df['algorithm'].str.replace(r'_([0-9]+)$', '', regex=True)

# Group and summarize
result = df.groupby(['experiment', 'algorithm'], as_index=False)[['time', 'yaml_size_kb']].max()

# Print result
print(result)
