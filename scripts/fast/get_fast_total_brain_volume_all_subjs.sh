#!/bin/bash
# Pre:  - run_mimosa.sh has been run successfully
#       - Bias-corrected skull-stripped T1 exists per subject at
#         $data_dir/sub-{empi}/ses-{date}/bias_correction/T1_brain_n4.nii.gz
#       - empi_ses_pairs.csv contains one empi,date pair per line (no header)
# Post: - fast/ directory created per subject with FSL FAST segmentation files
#       - total_fast_brain_volume_values.csv written per subject
# Uses: Loops through empi_ses_pairs.csv and submits one bsub job per subject
#       calling make_fast_files_single_subj.sh
# Dependencies: FSL, apptainer

data_dir=/project/msdepression/data/radiology_pulls_20260610/data
empi_ses_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_list_n3.csv"
scripts_dir=/project/msdepression/scripts/elena_mimosa_project_scripts
num_cores=1

echo "... Starting FAST segmentation ..."

job_count=1
while IFS= read -r line; do

    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    t1_input="$data_dir/sub-$sub/ses-$ses/bias_correction/T1_brain_n4.nii.gz"

    if [ ! -f "$t1_input" ]; then
        echo "  T1_brain_n4.nii.gz not found for sub-$sub ses-$ses. Skipping."
        continue
    fi

    echo "Submitting FAST job for sub-$sub ses-$ses..."
    bsub -J "fast_${job_count}" -n ${num_cores} \
        -o ${scripts_dir}/logfiles/fast_${sub}_${ses}.out \
        ${scripts_dir}/make_fast_files_single_subj.sh $sub $ses $data_dir

    ((job_count+=1))

done < "$empi_ses_pairs"

echo "All FAST jobs submitted."