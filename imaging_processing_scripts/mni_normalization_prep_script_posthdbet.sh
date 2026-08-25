#!/bin/bash
### MNI Normalization script
###pre- mimosa files stored in the mimosa output directories from the mimosa script
###post- new directory within /project/msdepression/data/radiology_pulls_20260610/subj_directories/data/sub*/ses*/mni_normalized,
###      and a file list with mni normed data ready for streamline filtering: /project/msdepression/data/radiology_pulls_20260610/file_lists/ready_for_streamline_filtering_n${num_subjs}.csv
###uses - 1. Within each subject -> within each session -> create mni_normalized
###       2. Copy mimosa binary mask from mimosa and T1 data from ws into mni_normalized
###       3. Create lists that contain all of the mni_normalized data for streamline filtering

##Set up directories
#subj_dirs="/project/msdepression/elena_mimosa_project/data/subj_directories_list"
path_to_proj=/project/msdepression/data/radiology_pulls_20260610/
outfile_direc="/project/msdepression/data/radiology_pulls_20260610/file_lists/"
empi_date_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_people_who_failed_skull_stripping_n9.csv"

num_subjs=$(more ${empi_date_pairs} | wc -l)
echo ${num_subjs}

outfile=${outfile_direc}/ready_for_streamline_filtering_n${num_subjs}.csv
mimosa_root="mimosa_mask.nii.gz"
brain_mask_root="brainmask_reg_flair.nii.gz"
t1="t1_n4_brain_reg_flair_ws.nii.gz"




#empi_ses_pairs="/project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_list.csv"

#set some parameters
#suffix="mimosa_volume_values"


#initialize ready_for_streamline_filtering.csv
rm rf ${outfile}
touch ${outfile}


echo "Starting mni_normalization setup for all subjects listed in ${mimosa_files_path}..."

# Loop through each line of CSV
while IFS= read -r line; do

    # Extract sub and ses
    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')

    echo "Making mni_normalization directories for sub-$sub ses-$ses..."

    # Construct the full path to the subject's anat folder
    directory="${path_to_proj}/data/sub-${sub}/ses-${ses}/"
    echo "Directory = ${directory}\n"

    if [ -d "${directory}/mni_normalized/" ]; then 
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

    #copy full path into outfile
    echo ${directory}/mni_normalized/ >> ${outfile}

   

done < "${empi_date_pairs}"

