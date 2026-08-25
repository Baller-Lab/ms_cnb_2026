#!/bin/bash
# Run lesion count (count step only) on subjects where mimosa has already completed
#
# Pre:  - run_mimosa.sh has been run successfully
#       - mimosa_mask.nii.gz exists at $path_to_proj/data/sub-{id}/ses-{date}/mimosa/
#       - empi_ses_pairs.csv contains one sub,ses pair per line (no header)
#         at /project/msdepression/elena_mimosa_project/data/empi_ses_pairs.csv
#
# Post: - count/ directory created per subject at $path_to_proj/data/sub-{id}/ses-{date}/count/
#       - sub-{id}_ses-{date}_connected_components.csv written to count/ for each subject
#
# Uses: Loops through each subject/session pair in empi_ses_pairs.csv. For each,
#       confirms mimosa_mask.nii.gz exists and count output does not already exist,
#       then submits lesion_count.sh in individual mode with --step count via apptainer.
#
# Dependencies: apptainer (containerized — R and all R package dependencies
#               including mimosa, ANTsR, fslr are handled within the container)

# Important notice: This calls the PennSIVE_neuro_pip that was saved inside mimosa. A little messy. 
#                   Also, would need to make a new version if you want to do BOTH mimosa and lesion_count together


# Set up paths
path_to_scripts=/project/msdepression/elena_mimosa_project/scripts/mimosa/PennSIVE_neuro_pip/
path_to_proj=/project/msdepression/data/radiology_pulls_20260610
sin_path="/project/singularity_images/neuror_latest.sif"
#empi_ses_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_list.csv"
empi_ses_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_people_who_failed_skull_stripping_n9.csv"

# Load required modules
module load apptainer

echo "Starting lesion count (cc) processing for all subjects listed in $empi_ses_pairs..."

while IFS= read -r line; do

    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    echo "Running lesion count for sub-$sub ses-$ses..."

    # Check mimosa_mask exists (required input for count step)
    mimosa_mask="$path_to_proj/data/sub-$sub/ses-$ses/mimosa/mimosa_mask.nii.gz"
    if [ ! -f "$mimosa_mask" ]; then
        echo "  mimosa_mask.nii.gz not found at $mimosa_mask. Skipping."
        continue
    fi

    # Skip if output already exists
    count_out="$path_to_proj/data/sub-$sub/ses-$ses/count/sub-${sub}_ses-${ses}_connected_components.csv"
    #if [ -f "$count_out" ]; then
     #   echo "  Lesion count output already exists for sub-$sub ses-$ses. Skipping."
      #  continue
    #fi

    bash ${path_to_scripts}/pipelines/lesion_count/code/bash/lesion_count.sh \
        -m ${path_to_proj} \
        -p sub-$sub \
        --ses ses-$ses \
        --step count \
        --method cc \
        --mode individual \
        --toolpath ${path_to_scripts} \
        --sinpath $sin_path \
        -c singularity

    echo "  Completed lesion count for sub-$sub ses-$ses"

done < "$empi_ses_pairs"

echo "All lesion count runs completed."
