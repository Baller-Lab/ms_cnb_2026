#!/bin/bash

#########     Welcome to  get_volume_of_mimosa_lesions.sh !  ##########3
## The purpose of this script is to extract the overall volume of lesion burden for each mimosa mask. 
## The goal is to use the output to answer the question: Does overall lesion burden (quantified by volume of lesions), irrespective of location, relate to depression diagnosis?

### Pre: File containing full paths to the mimosa binary masks:  /project/msdepression/data/melissa_martin_files/csv/mimosa_binary_masks_hcp_space_20211026_n2336
### Post: File containing ACCESSION_NUM, EXAM_DATA, volume_of_mimosa_lesions
### Uses: 	1) Reads in the file with full paths
###		2) Extracts the accession number and exam date
###		3) Performs 3dmaskave -quiet -mask SELF -sum ${binary_map} and writes to a file
### Dependencies: 1) Requires afni, so you need to xbash, and module load afni<tab complete>

### Opening Script: If nothing is entered, let person know we are using default mimosa path file, otherwise use file on command line

module load afni_openmp/20.1

#set some parameters
suffix="mimosa_volume_values"
num_subjs=104
date=20260619

echo "Greetings and welcome to the get_volume_of_mimosa_lesions script"
echo "This script takes a file with full paths to mimosa binary maps, and returns a file that has the empi, exam data, and overall volume of lesions in that map"
#set default path
default_mimosa_path="/project/msdepression/data/radiology_pulls_20260610/data/ready_for_streamline_filtering_n104.txt"
#default_mimosa_path="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_people_who_failed_skull_stripping_n9.csv"
echo "Default mimosa path $default_mimosa_path"
#set output directory for the volumes file
output_direc="/project/msdepression/results/"

if [ $# == 0 ]
then
    echo "We will use the default mimosa files path" $default_mimosa_path
    mimosa_files_path=$default_mimosa_path
else  
    mimosa_files_path=$1
fi

echo "Mimosa files path" $mimosa_files_path
#### initiate new file

#append "_volumes" to the end of the path
#suffix=$(echo ${mimosa_files_path} | perl -pe s'/.*\/(.*)/$1/g') #got rid of this to have more control over my mimosa output. 
output_csv=$output_direc/${suffix}_n${num_subjs}_${date}.csv

#get rid of old file if it exists, write new one and put in headers
rm -f $output_csv
touch $output_csv
echo "EMPI,EXAM_DATE,volume_of_mimosa_lesions" >> $output_csv

#loop through each file in the mimosa_file_path, extract empi/exam date, calculate volume, write to file
mimosa_files=$(cat ${mimosa_files_path})
for mimosa_file in $mimosa_files; do
    	echo "Mimosa file is" $mimosa_file
 
	#pulls out accession number and date, separated them by a comma
    	subj_sess=$(echo ${mimosa_file} | perl -pe s'/.*sub-(.*)\/ses-(.*)\/mni.*/$1,$2/g') #changed from \/r*
    
	#gets volume of binary mask
	volume=$(3dmaskave -quiet -mask SELF -sum ${mimosa_file})
        
	#writes to output file
	echo "${subj_sess},$volume" >> $output_csv
done

