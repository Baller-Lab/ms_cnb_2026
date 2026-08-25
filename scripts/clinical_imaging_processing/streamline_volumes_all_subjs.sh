#!/bin/bash

#### Welcome to the Region_making party #########
### Pre: Must have a file with full paths to the lesioned data 
### Post: Within each directory specified by the lesioned data, we will have a file that contains the volumes of the streamlines in each subject
### Uses: For use in MS depression - iterates through each subject and session
#dependencies: Using dsi studio downloaded 9/2021

default='/project/msdepression/data/radiology_pulls_20260610/data/ready_for_streamline_filtering_n104.txt'
num_cores=1

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

job_count=1
for lesion in ${lesion_paths}; do
    run_date=$(date +%Y%m%d_%H%M%S)
    echo "Working on file" $lesion
    bsub -J "job+${job_count}" -n ${num_cores} -o /project/msdepression/scripts/elena_mimosa_project_scripts/logfiles/3dmaskav_${run_date}_${job_count}.out /project/msdepression/scripts/elena_mimosa_project_scripts/make_streamline_volumes_single_subj_pmacs.sh $lesion
   #sh /project/msdepression/scripts/elena_mimosa_project_scripts/make_streamline_volumes_single_subj_pmacs.sh $lesion > /project/msdepression/scripts/elena_mimosa_project_scripts/logfiles/3dmaskav_${run_date}_${job_count}.out
    ((job_count+=1))
done
  
