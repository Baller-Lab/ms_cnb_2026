#!/bin/bash

#### Welcome to the Region_making party #########
### Pre: Must have a file with full paths to the lesioned data 
### Post: Within each directory specified by the lesioned data, will have a directory that has all tractography (ROA, ROI, Full)
### Uses: For use in MS depression - take a subject's mimosa lesions and generate the fiber tracts (individual fascicles) that run through it
#dependencies: Using dsi studio from docker, sif created by Tim 10/26/2021
#export PATH=${PATH}:/Applications/dsi_studio.app/Contents/MacOS/
set -euf -o pipefail

#set up global variables
num_cores=1
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${num_cores}


#set default paths 
template='/project/msdepression/templates/dti/HCP1065.1mm.fib.gz'
default='/project/msdepression/data/radiology_pulls_20260610/data/ready_for_streamline_filtering_n104.txt'
#default='/project/msdepression/data/melissa_martin_files/csv/erica_mini_mimosa_paths_n3'
fascicle_directory='/project/msdepression/templates/dti/HCP_YA1065_tractography/'

if [ $# == 0 ]
then
    echo "We will use the default mimosa path file" $default
    lesion_file=$default
else  
    lesion_file=$1
fi
echo "File being read is "$lesion_file
echo "... Starting to make lesions ..."

lesion_paths=$(cat $lesion_file)

# loop through each mimosa lesion map; lesion paths contain full paths to mimosa files in hcp space
job_count=1
for lesion in ${lesion_paths}; do
    run_date=$(date +%Y%m%d_%H%M%S)
	echo "working on ${lesion} ..."  
	bsub -J "job_${job_count}" -n ${num_cores} -o /project/msdepression/scripts/elena_mimosa_project_scripts/logfiles/out_roa_${run_date}_${job_count}.out /project/msdepression/scripts/elena_mimosa_project_scripts/indiv_mimosa_lesion_dsi_studio_script.sh $lesion
    #sh /project/msdepression/scripts/elena_mimosa_project_scripts/indiv_mimosa_lesion_dsi_studio_script.sh $lesion > /project/msdepression/scripts/elena_mimosa_project_scripts/logfiles/out_roa_${run_date}_${job_count}.out 
done
