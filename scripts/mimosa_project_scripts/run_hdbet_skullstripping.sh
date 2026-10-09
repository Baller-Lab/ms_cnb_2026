#!/bin/bash
# Pre:  - a T1w image exists at ${data_dir}/sub-{id}/ses-{date}/anat/*T1w.nii.gz
#       - SUB_SES_LIST: one "sub_id,ses_id" pair per line, no header (default: the whole cohort list below)
# Post: - HD-BET skull strip submitted for every scan; each writes ${data_dir}/sub-{id}/ses-{date}/t1_brain/
#         brain.nii.gz and brain_mask.nii.gz (PennSIVE skullstripping pipeline, individual mode = one LSF job each)
#       - an existing t1_brain/ (e.g. from a failed BET run) is copied to t1_brain_temp/ first, so
#         skullstripping.sh can make a fresh one
# Uses: HD-BET (deep-learning skull stripping) in place of the default BET skull strip, which failed on some
#       scans. Only the T1 is skull-stripped; MIMoSA masks the FLAIR with the T1 brain mask. The T1 is found by
#       suffix (*T1w.nii.gz) because some filenames carry a different ID than their folder -- the folder is
#       treated as ground truth.
#       Usage: ./run_hdbet_skullstripping.sh [SUB_SES_LIST]
#       Next step: run_mimosa.sh (wait for the HD-BET jobs to finish: t1_brain/brain.nii.gz must exist)
# Dependencies: LSF, apptainer, PennSIVE_neuro_pip, HD-BET container

# ---- base paths: edit these, everything below is built from them --------------
base_dir="/project/msdepression"
path_to_scripts="${base_dir}/scripts/PennSIVE_neuro_pip/"            # PennSIVE neuro pipelines
path_to_proj="${base_dir}/data/radiology_pulls_20260610"             # BIDS-style project (data/sub-*/ses-*/)
data_dir="${path_to_proj}/data"
sub_ses_list="${data_dir}/other_data/cubids/sub_ses_list.csv"         # used only if you don't pass one as $1
sin_path="/project/singularity_images/hd-bet_latest.sif"
# --------------------------------------------------------------------------------

if [ $# -gt 0 ]; then sub_ses_list=$1; fi
if [ ! -f "${sub_ses_list}" ]; then echo "ERROR: subject list ${sub_ses_list} not found" >&2; exit 1; fi
echo "Subject list: ${sub_ses_list} ($(grep -c . "${sub_ses_list}") rows)"

module load apptainer

while IFS=',' read -r sub ses; do
    [ -z "${sub}" ] && continue
    subj_dir="${data_dir}/sub-${sub}/ses-${ses}"
    echo "HD-BET for sub-${sub} ses-${ses}..."

    t1=$(find "${subj_dir}/anat" -maxdepth 1 -name "*T1w.nii.gz" 2>/dev/null | head -1)
    if [ -z "${t1}" ]; then
        echo "  No T1w file found for sub-${sub} ses-${ses}. Skipping."
        continue
    fi

    # keep any old skull strip (e.g. a failed BET run) in t1_brain_temp/, then clear t1_brain/
    t1_brain_dir="${subj_dir}/t1_brain"
    if [ -d "${t1_brain_dir}" ]; then
        mkdir -p "${t1_brain_dir}_temp"
        cp "${t1_brain_dir}"/* "${t1_brain_dir}_temp/."
        rm -r "${t1_brain_dir}"
    fi

    bash ${path_to_scripts}/pipelines/skullstripping/code/bash/skullstripping.sh \
        -m ${path_to_proj} \
        -p sub-${sub} \
        --ses ses-${ses} \
        -f "$(basename "${t1}")" \
        -t 'hdbet' \
        --mode individual \
        --toolpath ${path_to_scripts} \
        --sinpath ${sin_path} \
        -c singularity

    echo "  Submitted HD-BET for sub-${sub} ses-${ses}"
done < "${sub_ses_list}"

echo "All HD-BET jobs submitted. Logs: ${path_to_proj}/log/{output,error}/"
