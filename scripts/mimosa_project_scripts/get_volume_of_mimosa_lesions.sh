#!/bin/bash
# Pre:  - run_mimosa.sh has finished: mimosa/mimosa_mask.nii.gz exists per scan
#       - SUB_SES_LIST: one "sub_id,ses_id" pair per line, no header (default: the whole cohort list below)
# Post: - ${output_dir}/mimosa_volume_values_n<N>_<date_time>.csv with columns EMPI,EXAM_DATE,volume_of_mimosa_lesions
#         (one row per scan that has a MIMoSA mask; scans without one are skipped). New timestamped file each run,
#         so nothing is overwritten
# Uses: total white matter lesion volume = number of voxels in the binary MIMoSA mask (3dmaskave -sum; ~1 mm3
#       voxels, native FLAIR space), irrespective of location. Runs on the login node -- quick, no jobs submitted.
#       Usage: ./get_volume_of_mimosa_lesions.sh [SUB_SES_LIST]
# Dependencies: AFNI

# ---- base paths: edit these, everything below is built from them --------------
base_dir="/project/msdepression"
data_dir="${base_dir}/data/radiology_pulls_20260610/data"
sub_ses_list="${data_dir}/other_data/cubids/sub_ses_list.csv"         # used only if you don't pass one as $1
output_dir="${base_dir}/results/vol_mimosa_lesions"
# --------------------------------------------------------------------------------

if [ $# -gt 0 ]; then sub_ses_list=$1; fi
if [ ! -f "${sub_ses_list}" ]; then echo "ERROR: subject list ${sub_ses_list} not found" >&2; exit 1; fi

module load afni_openmp/20.1

num_subjs=$(grep -c . "${sub_ses_list}")
run_date=$(date +%Y%m%d_%H%M%S)
mkdir -p "${output_dir}"
output_csv="${output_dir}/mimosa_volume_values_n${num_subjs}_${run_date}.csv"
echo "Subject list: ${sub_ses_list} (${num_subjs} rows) -> ${output_csv}"

echo "EMPI,EXAM_DATE,volume_of_mimosa_lesions" > "${output_csv}"

while IFS=',' read -r sub ses; do
    [ -z "${sub}" ] && continue
    mimosa_file="${data_dir}/sub-${sub}/ses-${ses}/mimosa/mimosa_mask.nii.gz"
    if [ ! -f "${mimosa_file}" ]; then
        echo "  No MIMoSA mask for sub-${sub} ses-${ses}. Skipping."
        continue
    fi
    #number of voxels in the binary mask
    volume=$(3dmaskave -quiet -mask SELF -sum "${mimosa_file}")
    echo "${sub},${ses},${volume}" >> "${output_csv}"
done < "${sub_ses_list}"

echo "Done: $(($(grep -c . "${output_csv}") - 1)) scans written to ${output_csv}"
