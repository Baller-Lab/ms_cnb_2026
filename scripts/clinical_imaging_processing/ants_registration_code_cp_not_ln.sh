#!/bin/bash
### ANTS registration for MS Depression
##pre- requires ms mimosa file that contains the directory, mni brain: mni_icbm152_t1_tal_nlin_asym_09a.nii
##Post - ms participant T1w and mimosa registered to icbm_template space
##Uses - We have all of these great ms depression scans but they are in native space. This will get them into mni space so they can be used with HCP templates, both structural and diffusion
#Steps
## 1 - take all file paths to data with good qc, extract file paths, and make shadow directories with linksin out local data directory
## 2 - make the dilated mask
     #####mask (currently using the one that was dilated in afni, d3
     ## 3dmask_tool -input t1_n4_brainmask.nii.gz -prefix t1_n4_brainmask_d3.nii.gz -dilate_input 3
## 3 - for each subject, run the registration, and then apply the transpforms
##Dependencies: Using ANTs/2.3.5
# Set up paths
module load ANTs/2.3.5
module load afni_openmp
export ANTSPATH=/appl/ANTs-2.3.5/bin
NUM_CORES=4
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${NUM_CORES}
#######if it doesn't work, fix this ###
#export PATH=${ANTSPATH}:$PATH




#set default templatesfiles/paths

base_dir='/project/msdepression/scripts/elena_mimosa_project_scripts/'

#Primary directorie - CHANGE THESE IF ANYTHING EVER CHANGES, IT WILL UPDATE FILE NAMES BELOW

qc_file_path='/project/msdepression/data/radiology_pulls_20260610/data/subj_directories_to_rerun.txt'
#qc_file_path='/project/msdepression/data/radiology_pulls_20260610/data/ready_for_streamline_filtering.csv'
#qc_file_path='/project/msdepression/data/melissa_martin_files/csv/melissa_mimosa_100_and_75_paths'
mni_t1_root='mni_icbm152_t1_tal_nlin_asym_09a'
mask_dilation=3
mimosa_root="mimosa_mask_0.25"
brain_mask_root="brainmask_reg_flair"
t1="t1_n4_brain_reg_flair_ws.nii.gz"
out_data_path='/project/msdepression/data/radiology_pulls_20260610/data/'
mni_t1_direc='/project/msdepression/templates/mni_icbm152_nlin_asym_09a/'



#set outfile prefix
outfile_prefix='ms_t1_to_mni_icbm152'

#for transform
mimosa_path=${mimosa_root}.nii.gz #this is from mimosa output
mimosa_mni_hcp_path=${mimosa_root}_mni_hcp.nii.gz #output file prefix
affine_mat=${outfile_prefix}0GenericAffine.mat #affine output from last step
ms2mni_warp=${outfile_prefix}1Warp.nii.gz #warp from last step. There are a few, Warp, Warped InverseWarp, InverseWarped. I picked the one that matched out pnc output the closes


#making some secondary files
mni_t1_path="${mni_t1_direc}/${mni_t1_root}.nii"
mni_t1_target="${mni_t1_root}xbrainmask.nii"
brain_mask="${brain_mask_root}.nii.gz"
brain_mask_dilated="${brain_mask_root}_d${mask_dilation}.nii.gz"

directories=$(cat $qc_file_path)

#multiply with mni t1 to get appropriate coverage. Have to do it locally b/c afni
if [ -f "${mni_t1_direc}/${mni_t1_target}" ]; then
	echo "${mni_t1_direc}/${mni_t1_target} already exists"
else
	
	echo "making ${mni_t1_direc}/${mni_t1_target}"
	cd ${mni_t1_direc}
	3dcalc -a ${mni_t1_root}.nii -b ${mni_t1_root}_mask.nii -expr 'a*b' -prefix ${mni_t1_target}
	cd $base_dir
fi

#extract name of directory and create shadow directory in out own data directory, with appropriate file names
for directory in $directories; do
        sub_sess_run=$(echo ${directory} | perl -pe 's/.*(sub.*\/)mni.*/$1/') #grab sub/sess/run
		job_name=$(echo ${sub_sess_run} | tr '/' '_') #get job name to handle the /
        echo $sub_sess_run
        echo "##### Seeing if I need to make dir" ${directory} "\n"

	#remove directory if it already exists
	if [ -d "${directory}" ]; then 
		echo "${directory} already exists. Removing contents"
		rm -rf ${directory}/*
	else
		#make new directory
		echo "${directory} does not exist. Making it.\n"
        	mkdir -p ${directory}
	fi
	
#copy the mimosa path into it
    cp ${out_data_path}/${sub_sess_run}/mimosa/mimosa_mask.nii.gz ${directory}/.
	
	#threshold the mimosa mask at 0.25, based on what Melissa did previously, as well as the mimosa paper cutoffs for sensitivity
	3dcalc -a "${out_data_path}/${sub_sess_run}/mimosa/mimosa_mask.nii.gz" \
       -expr 'ispositive(a-0.25)' \
       -prefix "${directory}/${mimosa_path}"

    #copy the T1 into it
    cp ${out_data_path}/${sub_sess_run}/whitestripe/FLAIR_space/${t1} ${directory}/.
    
    #copy the registration data into it
    cp ${out_data_path}/${sub_sess_run}/registration/FLAIR_space/${brain_mask_root}.nii.gz ${directory}/.
        
	#copy mni target (mni template xmask dilation) 
	cp ${mni_t1_direc}/${mni_t1_target} ${directory}/.

        #go into directory for afni stuff, then pop back out
        cd ${directory}

        	#make the dilated mask
        	3dmask_tool -input ${brain_mask} -prefix ${brain_mask_dilated} -dilate_input ${mask_dilation}
	cd ${base_dir}

        	#multiply with mni t1 to get appropriate coverage - this is the problem!!! 
        	#3dcalc -a ${mni_t1_root}.nii -b ${mni_t1_root}_mask.nii -expr 'a*b' -prefix ${mni_t1_target}

         
	#### Run registration

	#### Run registration
	bsub -J "job_${job_name}" -n ${NUM_CORES} -o /project/msdepression/scripts/logfiles/"out_reg_${job_name}" antsRegistrationSyN.sh -d 3 -f ${directory}/${mni_t1_target} -m ${directory}/${t1} -o ${directory}/${outfile_prefix} -x ${directory}/${brain_mask_dilated}

	# apply mimosa transform to mni space; wait for registration to finish first (-w flag)
	# -e 0 = scalar (not tensor), -n GenericLabel = appropriate interpolation for binary mask
	bsub -w "done(job_${job_name})" -n ${NUM_CORES} -o /project/msdepression/scripts/logfiles/"out_transf_${job_name}" antsApplyTransforms -e 0 -d 3 -i ${directory}/${mimosa_path} -o ${directory}/${mimosa_mni_hcp_path} -r ${directory}/${mni_t1_target} -t ${directory}/${ms2mni_warp} -t ${directory}/${affine_mat} -n GenericLabel
       # bsub -J "job_${sub_sess_run}" -n ${NUM_CORES} -o /project/msdepression/scripts/logfiles/"out_reg${sub_sess_run}" antsRegistrationSyN.sh -d 3 -f ${directory}/${mni_t1_target} -m ${directory}/${t1} -o ${directory}/${outfile_prefix} -x ${directory}/${brain_mask_dilated}

        #now actually do the transform${brain
    	# bsub -w "done(job_${sub_sess_run})" -n ${NUM_CORES} -o /project/msdepression/scripts/logfiles/"out_transf${sub_sess_run}" antsApplyTransforms -e 0 -d 3 -i ${directory}/${mimosa_path} -o ${directory}/${mimosa_mni_hcp_path} -r ${directory}/${mni_t1_target} -t ${directory}/${ms2mni_warp} -t ${directory}/${affine_mat} -n GenericLabel

done
