#!/bin/bash
# Pre:  - make_fast_files_single_subj.sh has been run for all subjects
#       - total_fast_brain_volume_values.csv exists per subject in fast/ directory
# Post: - /project/msdepression/results/total_fast_brain_volumes_n104.csv created
#         with columns: EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume
# Uses: Loops through empi_ses_pairs.csv, finds each subject's per-subject CSV,
#       and appends the data row to the consolidated output file
# Dependencies: bash

data_dir=/project/msdepression/data/radiology_pulls_20260610/data
empi_ses_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_list.csv"
output_csv=/project/msdepression/results/total_fast_brain_volumes_n104.csv

#mkdir -p /project/msdepression/results

rm -f $output_csv
echo "EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume" > $output_csv

while IFS= read -r line; do

    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    indiv_csv="${data_dir}/sub-${sub}/ses-${ses}/fast/total_fast_brain_volume_values.csv"

    if [ ! -f "$indiv_csv" ]; then
        echo "  No volume CSV found for sub-$sub ses-$ses. Skipping."
        continue
    fi

    tail -1 ${indiv_csv} >> ${output_csv}

done < "$empi_ses_pairs"

echo "Done. Output written to $output_csv"
