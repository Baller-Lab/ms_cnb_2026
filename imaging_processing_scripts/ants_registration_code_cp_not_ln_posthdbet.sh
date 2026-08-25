#!/bin/bash
### ANTS registration for MS Depression
##Pre:  - mimosa_mask.nii.gz exists at {subject_dir}/mimosa/
##      - t1_n4_brain_reg_flair_ws.nii.gz exists at {subject_dir}/whitestripe/FLAIR_space/
##      - brainmask_reg_flair.nii.gz exists at {subject_dir}/registration/FLAIR_space/
##      - MNI T1 template at mni_t1_direc (mni_icbm152_t1_tal_nlin_asym_09a.nii + _mask.nii)
##Post: - T1 and mimosa lesion mask registered to MNI (ICBM152) space per subject
##      - Outputs in {subject_dir}/mni_normalized/
##Uses: - ANTs SyN registration to warp native-space T1 to MNI template, then applies
##        the same transforms to the MIMOSA lesion mask so it can be overlaid with HCP templates
##Steps:
##  1 - build skull-stripped MNI reference (once, if not already done)
##  2 - per subject: copy inputs, dilate brain mask, submit registration job
##  3 - apply transforms to MIMOSA mask after registration completes (job dependency)
##Dependencies: ANTs/2.3.5, afni_openmp

# Set up paths
module load ANTs/2.3.5
module load afni_openmp
export ANTSPATH=/appl/ANTs-2.3.5/bin
NUM_CORES=4
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${NUM_CORES}
#export PATH=${ANTSPATH}:$PATH  # uncomment if antsRegistrationSyN.sh not found

# Paths - CHANGE THESE IF ANYTHING EVER CHANGES
base_dir='/project/msdepression/scripts/elena_mimosa_project_scripts'
path_to_proj='/project/msdepression/data/radiology_pulls_20260610'
empi_date_pairs="${path_to_proj}/data/other_data/cubids/sub_ses_people_who_failed_skull_stripping_n9.csv"
mni_t1_direc='/project/msdepression/templates/mni_icbm152_nlin_asym_09a'
outfile_direc="${path_to_proj}/file_lists"
logfile_direc='/project/msdepression/scripts/logfiles'

# File name roots
mni_t1_root='mni_icbm152_t1_tal_nlin_asym_09a'
mimosa_root='mimosa_mask'
brain_mask_root='brainmask_reg_flair'
t1='t1_n4_brain_reg_flair_ws.nii.gz'
outfile_prefix='ms_t1_to_mni_icbm152'
mask_dilation=3
queue='bbl_normal'

# Derived file names
mimosa_path="${mimosa_root}.nii.gz"
mimosa_mni_hcp_path="${mimosa_root}_mni_hcp.nii.gz"
brain_mask="${brain_mask_root}.nii.gz"
brain_mask_dilated="${brain_mask_root}_d${mask_dilation}.nii.gz"
mni_t1_target="${mni_t1_root}xbrainmask.nii"
affine_mat="${outfile_prefix}0GenericAffine.mat"
ms2mni_warp="${outfile_prefix}1Warp.nii.gz"

# Count subjects
num_subjs=$(wc -l < "${empi_date_pairs}")
echo "Processing ${num_subjs} subjects"

# Output directories
mkdir -p "${outfile_direc}"
mkdir -p "${logfile_direc}"
outfile="${outfile_direc}/mni_normalized_n${num_subjs}.txt"

# Build skull-stripped MNI reference once (T1 * mask)
if [ -f "${mni_t1_direc}/${mni_t1_target}" ]; then
    echo "${mni_t1_direc}/${mni_t1_target} already exists, skipping."
else
    echo "Building skull-stripped MNI reference: ${mni_t1_target}"
    cd "${mni_t1_direc}"
    3dcalc -a ${mni_t1_root}.nii -b ${mni_t1_root}_mask.nii -expr 'a*b' -prefix ${mni_t1_target}
    cd "${base_dir}"
fi

# Loop through each subject/session
while IFS= read -r line; do

    sub=$(echo "$line" | perl -pe 's/(.*),(.*)/$1/')
    ses=$(echo "$line" | perl -pe 's/(.*),(.*)/$2/')
    directory="${path_to_proj}/data/sub-${sub}/ses-${ses}"

    echo "Processing sub-${sub} ses-${ses}..."
    echo "  Directory: ${directory}"

    # Set up mni_normalized working directory
    if [ -d "${directory}/mni_normalized" ]; then
        echo "  mni_normalized exists, clearing contents."
        rm -f "${directory}/mni_normalized"/*
    else
        echo "  Creating mni_normalized."
        mkdir -p "${directory}/mni_normalized"
    fi

    # Copy inputs into mni_normalized
    cp "${directory}/mimosa/${mimosa_path}"                  "${directory}/mni_normalized/."
    cp "${directory}/whitestripe/FLAIR_space/${t1}"          "${directory}/mni_normalized/."
    cp "${directory}/registration/FLAIR_space/${brain_mask}" "${directory}/mni_normalized/."

    # Dilate brain mask for ANTs -x flag
    if [ ! -f "${directory}/mni_normalized/${brain_mask_dilated}" ]; then
        echo "  Dilating brain mask by ${mask_dilation} voxels..."
        3dmask_tool \
            -input  "${directory}/mni_normalized/${brain_mask}" \
            -prefix "${directory}/mni_normalized/${brain_mask_dilated}" \
            -dilate_input ${mask_dilation}
    else
        echo "  Dilated mask already exists, skipping."
    fi

    # Submit registration job
    job_name="${sub}_${ses}"
    bsub \
        -J "reg_${job_name}" \
        -q ${queue} \
        -n ${NUM_CORES} \
        -o "${logfile_direc}/out_reg_${job_name}.log" \
        antsRegistrationSyN.sh \
            -d 3 \
            -f "${directory}/mni_normalized/${mni_t1_target}" \
            -m "${directory}/mni_normalized/${t1}" \
            -o "${directory}/mni_normalized/${outfile_prefix}" \
            -x "${directory}/mni_normalized/${brain_mask_dilated}"

    # Apply transforms to MIMOSA mask after registration completes
    # -e 0 = scalar image, -n GenericLabel = nearest-neighbor interpolation for binary mask
    bsub \
        -w "done(reg_${job_name})" \
        -q ${queue} \
        -n ${NUM_CORES} \
        -o "${logfile_direc}/out_transf_${job_name}.log" \
        antsApplyTransforms \
            -e 0 \
            -d 3 \
            -i "${directory}/mni_normalized/${mimosa_path}" \
            -o "${directory}/mni_normalized/${mimosa_mni_hcp_path}" \
            -r "${directory}/mni_normalized/${mni_t1_target}" \
            -t "${directory}/mni_normalized/${ms2mni_warp}" \
            -t "${directory}/mni_normalized/${affine_mat}" \
            -n GenericLabel

    # Log output directory
    echo "${directory}/mni_normalized/" >> "${outfile}"

done < "${empi_date_pairs}"

echo "All jobs submitted. Paths written to ${outfile}"