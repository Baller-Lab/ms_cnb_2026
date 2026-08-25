#!/bin/bash
### MNI Normalization script
###pre- mimosa files stored in the mimosa output directories from the mimosa script
###post- new directory within /project/msdepression/data/radiology_pulls_20260610/subj_directories/data/sub*/ses*/mni_normalized,
###      and a file list with mni normed data ready for streamline filtering: /project/msdepression/data/radiology_pulls_20260610/data/ready_for_streamline_filtering.csv
###uses - 1. Within each subject -> within each session -> create mni_normalized
###       2. Copy mimosa binary mask from mimosa and T1 data from ws into mni_normalized
###       3. Create lists that contain all of the mni_normalized data for streamline filtering

##Set up directories
#subj_dirs="/project/msdepression/elena_mimosa_project/data/subj_directories_list"
#outfile_direc="/project/msdepression/elena_mimosa_project/data/"
subj_dirs="/project/msdepression/data/radiology_pulls_20260610/data/subj_directories_list.txt"
outfile_direc="/project/msdepression/data/radiology_pulls_20260610/data/"
outfile="${outfile_direc}/ready_for_streamline_filtering.csv"
mimosa_root="mimosa_mask.nii.gz"
brain_mask_root="brainmask_reg_flair.nii.gz"
t1="t1_n4_brain_reg_flair_ws.nii.gz"

#initialize ready_for_streamline_filtering.csv
rm rf ${outfile}
touch ${outfile}

#get all directories
directories=$(cat ${subj_dirs})

for directory in ${directories}; do
    echo ${directory}
    #make the new mni normalized directory
    if [ -d "${directory}/mni_normalized" ]; then 
		echo "${directory}/mni_normalized already exists. Removing contents"
		rm ${directory}/mni_normalized/*
	else
		#make new directory
		echo "${directory}/mni_normalized does not exist. Making it."
        	  mkdir ${directory}/mni_normalized
	fi
  

    #copy the mimosa path into it
    cp ${directory}/mimosa/${mimosa_root} ${directory}/mni_normalized/.

    #copy the T1 into it
    cp ${directory}/whitestripe/FLAIR_space/${t1} ${directory}/mni_normalized/.
    
    #copy the registration data into it
    cp ${directory}/registration/FLAIR_space/${brain_mask_root} ${directory}/mni_normalized/.

    #copy full path into ready_for_streamline_filtering.csv
    echo ${directory}/mni_normalized/ >> ${outfile}
done


