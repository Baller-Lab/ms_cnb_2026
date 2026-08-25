#!/bin/bash
# Consolidate lesion count CSVs into a single results file
#
# Pre:  - count/ directories exist per subject with *_connected_components.csv files
#         at /project/msdepression/data/radiology_pulls_20260610/data/sub-{id}/ses-{date}/count/
#
# Post: - /project/msdepression/results/lesion_count_n104.csv created with columns:
#         EMPI, date, lesion_count
#
# Uses: Loops through all connected_components.csv files, extracts the lesion count
#       (second column, second row), and parses empi and date from the filename.
#
# Dependencies: bash, awk

data_dir=/project/msdepression/data/radiology_pulls_20260610/data
out_file=/project/msdepression/results/lesion_count_n104.csv


echo "EMPI,date,lesion_count" > $out_file

for csv in $(find $data_dir -name "*_connected_components.csv"); do

    # Extract empi and date from filename (sub-{empi}_ses-{date}_connected_components.csv)
    filename=$(basename $csv)
    empi=$(echo $filename | sed 's/sub-\(.*\)_ses-.*/\1/')
    date=$(echo $filename | sed 's/.*_ses-\(.*\)_connected_components.csv/\1/')

    # Extract lesion count (second column, second row, strip quotes)
    lesion_count=$(awk -F',' 'NR==2 {gsub(/"/, "", $2); print $2}' $csv)

    echo "$empi,$date,$lesion_count" >> $out_file

done

echo "Done. Output written to $out_file"
