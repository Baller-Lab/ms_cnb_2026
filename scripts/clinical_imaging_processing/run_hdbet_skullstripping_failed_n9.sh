#!/bin/bash
# Run HDBET skullstripping on subjects who failed BET skullstripping (n=9)
#
# Pre:  - T1w.nii.gz exists at $path_to_proj/data/sub-{id}/ses-{date}/anat/
#       - sub_ses_people_who_failed_skull_stripping_n9.csv contains one sub,ses
#         pair per line (no header)
#         at /project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/
#       - Existing t1_brain/ directories (from failed BET runs) are moved to
#         t1_brain_temp/ before processing so skullstripping.sh can mkdir fresh
#
# Post: - t1_brain/ directory created per subject at
#         $path_to_proj/data/sub-{id}/ses-{date}/t1_brain/
#
# Uses: Loops through each subject/session pair in the failed skullstripping CSV.
#       For each, moves any existing t1_brain/ to t1_brain_temp/, finds the T1w
#       file generically by suffix (some filenames have mismatched sub IDs due to
#       cuBIDS labeling issues — folder placement is treated as ground truth), then
#       submits skullstripping.sh in individual mode with MASS via apptainer.
#       Only T1w is skull-stripped; per MIMOSA convention, FLAIR is masked using
#       the T1 brain mask rather than skull-stripped independently.
#
# Dependencies: apptainer (containerized — HDBET and all dependencies are handled
#               within the container)

# Set up paths
path_to_scripts=/project/msdepression/elena_mimosa_project/scripts/mimosa/PennSIVE_neuro_pip/
path_to_proj=/project/msdepression/data/radiology_pulls_20260610
#sin_path="/project/singularity_images/neuror_latest.sif"
sin_path="/project/singularity_images/hd-bet_latest.sif"
sub_ses_list="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_people_who_failed_skull_stripping_n9.csv"

# Load required modules
module load apptainer

echo "Starting HDBET skullstripping for subjects listed in $sub_ses_list..."

while IFS= read -r line; do

    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    echo "Running HDBET skullstripping for sub-$sub ses-$ses..."

    t1=$(ls ${path_to_proj}/data/sub-${sub}/ses-${ses}/anat/*T1w.nii.gz 2>/dev/null | head -1)

    if [ -z "$t1" ]; then
        echo "  No T1w file found for sub-$sub ses-$ses. Skipping."
        continue
    fi

    # Move stale t1_brain/ from failed BET run so skullstripping.sh can mkdir fresh
    
    t1_brain_dir="${path_to_proj}/data/sub-${sub}/ses-${ses}/t1_brain"
    echo "here is the brain directory ${t1_brain_dir}"
    if [ -d "$t1_brain_dir" ]; then
        mkdir ${t1_brain_dir}_temp
        cp ${t1_brain_dir}/* "${t1_brain_dir}_temp/."
        rm -r ${t1_brain_dir}
    fi

    bash ${path_to_scripts}/pipelines/skullstripping/code/bash/skullstripping.sh \
        -m ${path_to_proj} \
        -p sub-$sub \
        --ses ses-$ses \
        -f "$(basename "$t1")" \
        -t 'hdbet' \
        --mode individual \
        --toolpath ${path_to_scripts} \
        --sinpath $sin_path \
        -c singularity

    echo "  Completed MASS skullstripping for sub-$sub ses-$ses"

done < "$sub_ses_list"

echo "All HDBET skullstripping runs completed."