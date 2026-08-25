#!/bin/bash
# Copy and rename registration check files for each subject
#
# Pre:  - mni_normalized/ directory exists per subject with source files
#       - sub_ses_list.csv contains one empi,date pair per line (no header)
#       - check_reg/ directory exists at $data_dir/check_reg/
#
# Post: - For each subject, 4 files copied to $data_dir/check_reg/ renamed as:
#         sub-{empi}_ses-{date}_mimosa_mask_0.25_mni_hcp.nii.gz
#         sub-{empi}_ses-{date}_ms_t1_to_mni_icbm1521Warp.nii.gz
#         sub-{empi}_ses-{date}_mimosa_mask_0.25.nii.gz
#         sub-{empi}_ses-{date}_t1_n4_brain_reg_flair_ws.nii.gz
#
# Uses: Loops through sub_ses_list.csv, copies files from each subject's
#       mni_normalized/ directory into the shared check_reg/ directory with
#       subject-prefixed filenames
#
# Dependencies: bash

data_dir=/project/msdepression/data/radiology_pulls_20260610/data
sub_ses_list=/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_list.csv
check_reg_dir=${data_dir}/check_reg

mkdir -p ${check_reg_dir}

files_to_copy=(
    "mimosa_mask_0.25_mni_hcp.nii.gz"
    "ms_t1_to_mni_icbm152Warped.nii.gz"
    "mimosa_mask_0.25.nii.gz"
    "t1_n4_brain_reg_flair_ws.nii.gz"
)

while IFS= read -r line; do

    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    src_dir="${data_dir}/sub-${sub}/ses-${ses}/mni_normalized"

    if [ ! -d "$src_dir" ]; then
        echo "  mni_normalized not found for sub-$sub ses-$ses. Skipping."
        continue
    fi

    for f in "${files_to_copy[@]}"; do
        src="${src_dir}/${f}"
        dst="${check_reg_dir}/sub-${sub}_ses-${ses}_${f}"

        if [ ! -f "$src" ]; then
            echo "  File not found, skipping: $src"
            continue
        fi

        if [ -f "$dst" ]; then
            echo "  Already exists, skipping: $dst"
            continue
        fi

        cp "$src" "$dst"
        echo "  Copied: $dst"
    done

done < "$sub_ses_list"

echo "Done."
