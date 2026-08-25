#!/bin/bash

#########     Welcome to  get_volume_of_mimosa_lesions.sh !  ##########3
## The purpose of this script is to extract the overall volume of lesion burden for each mimosa mask. 
## The goal is to use the output to answer the question: Does overall lesion burden (quantified by volume of lesions), irrespective of location, relate to depression diagnosis?

### Pre: Mimosa files (mimosa_mask.nii.gz) already calculated
### Post: File containing ACCESSION_NUM,  EXAM_DATA, volume_of_mimosa_lesions
### Uses: 	1) finds the scans
###		    2) Performs 3dmaskave -quiet -mask SELF -sum ${binary_map} and writes to a file
### Dependencies: 1) Requires afni, so you need to module load afni<tab complete> (written in)

### Opening Script: If nothing is entered, let person know we are using default mimosa path file, otherwise use file on command line

module load afni_openmp/20.1

# Set up paths
path_to_scripts=/project/msdepression/elena_mimosa_project/scripts/mimosa/PennSIVE_neuro_pip/
path_to_proj=/project/msdepression/data/radiology_pulls_20260610/
empi_ses_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_list.csv"

#set some parameters
suffix="mimosa_volume_values"
num_subjs=$(more ${empi_ses_pairs} | wc -l)
echo ${num_subjs}
date=$(date +%Y%m%d_%H%M%S)
echo ${date}

echo "Greetings and welcome to the get_volume_of_mimosa_lesions script"
echo "This script gets lesion volumes of mimosa binary maps in native space, and returns a file that has the empi, exam data, and overall volume of lesions in that map"

echo "Default mimosa path $empi_ses_pairs"

#set output directory for the volumes file
output_direc="/project/msdepression/results/vol_mimosa_lesions/"

if [ $# == 0 ]
then
    echo "We will use the default mimosa files path" $empi_ses_pairs
    mimosa_files_path=$empi_ses_pairs
else  
    mimosa_files_path=$1
fi

echo "Mimosa files path" $mimosa_files_path

#### initiate new file
output_csv=$output_direc/${suffix}_n${num_subjs}_${date}.csv

#get rid of old file if it exists, write new one and put in headers
rm -f $output_csv
touch $output_csv
echo "EMPI,EXAM_DATE,volume_of_mimosa_lesions" >> $output_csv


echo "Starting mimosa volume count processing for all subjects listed in ${mimosa_files_path}..."

# Loop through each line of CSV
while IFS= read -r line; do

    # Extract sub and ses
    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    echo "Running mimosa volume calc for sub-$sub ses-$ses..."

    # Construct the full path to the subject's anat folder
    mimosa_dir="$path_to_proj/data/sub-$sub/ses-$ses/mimosa"

    # Check if directory exists
    if [ -d "$mimosa_dir" ]; then
        echo "  Found anat directory: $mimosa_dir"
        
		mimosa_file="${mimosa_dir}/mimosa_mask.nii.gz"
	
    
	#gets volume of binary mask
	volume=$(3dmaskave -quiet -mask SELF -sum ${mimosa_file})
        
	#writes to output file
	echo "${sub},${ses},$volume" >> $output_csv
      

    echo "  Completed mimosa volume calc for sub-$sub ses-$ses"
    else
       echo "  Mimosa directory not found: $mimosa_dir. Skipping."
    fi

done < "${mimosa_files_path}"

echo "All mimosa runs completed."