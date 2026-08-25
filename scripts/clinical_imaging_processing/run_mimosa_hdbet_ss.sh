#!/bin/bash
# 11/18/25
# Run MIMoSA on all subjects in the provided list
# Pre: empi_ses_mim_pull.sh has been run to pull all sub/ses pairs of interest into /project/msdepression/elena_mimosa_project/subj_directories/data
# Post: MIMoSA output in /project/msdepression/elena_mimosa_project/subj_directories/data/sub-ID

# Set up paths
path_to_scripts=/project/msdepression/elena_mimosa_project/scripts/mimosa/PennSIVE_neuro_pip/
path_to_proj=/project/msdepression/data/radiology_pulls_20260610/
#path_to_proj=/project/msdepression/elena_mimosa_project/subj_directories
sin_path="/project/singularity_images/neuror_latest.sif"
#sin_path="/project/singularity_images/neuror_4.2.sif"
empi_ses_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_people_who_failed_skull_stripping_n9.csv"
#empi_ses_pairs="/project/msdepression/elena_mimosa_project/data/mimosa_prep_20251023/mimosa_empi_ses_temp.csv"

# Load required modules
module load R
module load fsl/6.0.3#
module load apptainer

#bash ${path_to_scripts}/pipelines/mimosa/code/bash/mimosa.sh -m ${path_to_proj} -p sub-10936877 --ses ses-20241215 -t "*_T1w.nii.gz" -f "*_FLAIR.nii.gz" -s TRUE --mode individual --toolpath ${path_to_scripts} --sinpath $sin_path


echo "Starting mimosa processing for all subjects listed in $empi_ses_pairs..."

# Loop through each line of CSV
while IFS= read -r line; do

    # Extract sub and ses
    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    echo "Running mimosa for sub-$sub ses-$ses..."

    # Construct the full path to the subject's anat folder
    anat_dir="$path_to_proj/data/sub-$sub/ses-$ses/anat"

    # Check if directory exists
    if [ -d "$anat_dir" ]; then
        echo "  Found anat directory: $anat_dir"
        # Run mimosa
       bash ${path_to_scripts}/pipelines/mimosa/code/bash/mimosa.sh -m ${path_to_proj} -p sub-$sub --ses ses-$ses -t "*_T1w.nii.gz" -f "*_FLAIR.nii.gz" --mode individual --toolpath ${path_to_scripts} --sinpath $sin_path -c singularity #-s TRUE

       echo "  Completed mimosa for sub-$sub ses-$ses"
    else
       echo "  Anat directory not found: $anat_dir. Skipping."
    fi

done < "$empi_ses_pairs"

echo "All mimosa runs completed."

