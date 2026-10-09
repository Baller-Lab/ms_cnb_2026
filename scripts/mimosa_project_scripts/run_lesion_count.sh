#!/bin/bash
# Pre:  - run_mimosa.sh has finished: mimosa/mimosa_mask.nii.gz exists per scan
#       - SUB_SES_LIST: one "sub_id,ses_id" pair per line, no header (default: the whole cohort list below)
# Post: - lesion count submitted per scan (PennSIVE lesion_count pipeline, count step, connected components);
#         each writes count/sub-{id}_ses-{date}_connected_components.csv. Existing outputs are overwritten.
# Uses: number of separate lesions in the MIMoSA mask (connected components; lesions that touch count as one).
#       Scans without a MIMoSA mask (e.g. no usable FLAIR) are skipped.
#       Usage: ./run_lesion_count.sh [SUB_SES_LIST]
#       Next step: create_lesion_count_csv.sh (once every job has finished)
# Dependencies: LSF, apptainer, PennSIVE_neuro_pip, neuroR container

# ---- base paths: edit these, everything below is built from them --------------
base_dir="/project/msdepression"
path_to_scripts="${base_dir}/scripts/PennSIVE_neuro_pip/"
path_to_proj="${base_dir}/data/radiology_pulls_20260610"
data_dir="${path_to_proj}/data"
sub_ses_list="${data_dir}/other_data/cubids/sub_ses_list.csv"         # used only if you don't pass one as $1
sin_path="/project/singularity_images/neuror_latest.sif"
# --------------------------------------------------------------------------------

if [ $# -gt 0 ]; then sub_ses_list=$1; fi
if [ ! -f "${sub_ses_list}" ]; then echo "ERROR: subject list ${sub_ses_list} not found" >&2; exit 1; fi
echo "Subject list: ${sub_ses_list} ($(grep -c . "${sub_ses_list}") rows)"

module load apptainer

while IFS=',' read -r sub ses; do
    [ -z "${sub}" ] && continue
    mimosa_mask="${data_dir}/sub-${sub}/ses-${ses}/mimosa/mimosa_mask.nii.gz"
    if [ ! -f "${mimosa_mask}" ]; then
        echo "No MIMoSA mask for sub-${sub} ses-${ses} (${mimosa_mask}). Skipping."
        continue
    fi

    bash ${path_to_scripts}/pipelines/lesion_count/code/bash/lesion_count.sh \
        -m ${path_to_proj} \
        -p sub-${sub} \
        --ses ses-${ses} \
        --step count \
        --method cc \
        --mode individual \
        --toolpath ${path_to_scripts} \
        --sinpath ${sin_path} \
        -c singularity

    echo "Submitted lesion count for sub-${sub} ses-${ses}"
done < "${sub_ses_list}"

echo "All lesion count jobs submitted. Logs: ${path_to_proj}/log/{output,error}/"
