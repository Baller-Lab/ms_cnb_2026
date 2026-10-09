#!/bin/bash
# Pre:  - run_hdbet_skullstripping.sh has finished: t1_brain/brain.nii.gz + brain_mask.nii.gz exist per scan
#       - T1w and FLAIR images in ${data_dir}/sub-{id}/ses-{date}/anat/ (*_T1w.nii.gz, *_FLAIR.nii.gz)
#       - SUB_SES_LIST: one "sub_id,ses_id" pair per line, no header (default: the whole cohort list below)
# Post: - MIMoSA submitted for every scan (PennSIVE mimosa pipeline, individual mode = one LSF job each); each writes
#         mimosa/mimosa_mask.nii.gz (binary lesion map, FLAIR space), bias_correction/T1_brain_n4.nii.gz (used by FAST),
#         registration/FLAIR_space/ and whitestripe/FLAIR_space/
# Uses: MIMoSA white matter lesion segmentation on the HD-BET-skull-stripped T1 (MIMoSA's own skull strip is
#       turned off -- no -s TRUE -- so it uses the HD-BET brain mask).
#       HD-BET names its mask <output>_mask -> t1_brain/brain_mask.nii.gz, but the MIMoSA R script only looks for
#       *brainmask.nii.gz and stops right after bias correction with "readNIfTI ... File(s) not found". So before
#       each MIMoSA call the mask is copied (not moved) to t1_brain/brainmask.nii.gz.
#       Usage: ./run_mimosa.sh [SUB_SES_LIST]
#       Next steps: run_lesion_count.sh, get_volume_of_mimosa_lesions.sh, and FAST (fast_project_scripts)
# Dependencies: LSF, R, FSL, apptainer, PennSIVE_neuro_pip, neuroR container

# ---- base paths: edit these, everything below is built from them --------------
base_dir="/project/msdepression"
path_to_scripts="${base_dir}/scripts/PennSIVE_neuro_pip/"
path_to_proj="${base_dir}/data/radiology_pulls_20260610/"
data_dir="${path_to_proj}/data"
sub_ses_list="${data_dir}/other_data/cubids/sub_ses_list.csv"         # used only if you don't pass one as $1
sin_path="/project/singularity_images/neuror_latest.sif"
# --------------------------------------------------------------------------------

if [ $# -gt 0 ]; then sub_ses_list=$1; fi
if [ ! -f "${sub_ses_list}" ]; then echo "ERROR: subject list ${sub_ses_list} not found" >&2; exit 1; fi
echo "Subject list: ${sub_ses_list} ($(grep -c . "${sub_ses_list}") rows)"

module load R
module load fsl/6.0.3
module load apptainer

while IFS=',' read -r sub ses; do
    [ -z "${sub}" ] && continue
    subj_dir="${data_dir}/sub-${sub}/ses-${ses}"
    echo "MIMoSA for sub-${sub} ses-${ses}..."

    if [ ! -d "${subj_dir}/anat" ]; then
        echo "  Anat directory not found: ${subj_dir}/anat. Skipping."
        continue
    fi

    # HD-BET mask -> the name MIMoSA expects (see header)
    t1_brain_dir="${subj_dir}/t1_brain"
    if [ -f "${t1_brain_dir}/brain_mask.nii.gz" ] && [ ! -f "${t1_brain_dir}/brainmask.nii.gz" ]; then
        cp -p "${t1_brain_dir}/brain_mask.nii.gz" "${t1_brain_dir}/brainmask.nii.gz"
        echo "  Copied HD-BET brain_mask.nii.gz -> brainmask.nii.gz (name MIMoSA expects)"
    fi
    if [ ! -f "${t1_brain_dir}/brainmask.nii.gz" ] || [ ! -f "${t1_brain_dir}/brain.nii.gz" ]; then
        echo "  WARNING: no t1_brain/brain.nii.gz + brainmask.nii.gz for sub-${sub} ses-${ses} -- run HD-BET first; MIMoSA will fail" >&2
    fi

    bash ${path_to_scripts}/pipelines/mimosa/code/bash/mimosa.sh \
        -m ${path_to_proj} \
        -p sub-${sub} \
        --ses ses-${ses} \
        -t "*_T1w.nii.gz" \
        -f "*_FLAIR.nii.gz" \
        --mode individual \
        --toolpath ${path_to_scripts} \
        --sinpath ${sin_path} \
        -c singularity

    echo "  Submitted MIMoSA for sub-${sub} ses-${ses}"
done < "${sub_ses_list}"

echo "All MIMoSA jobs submitted. Logs: ${path_to_proj}/log/{output,error}/"
