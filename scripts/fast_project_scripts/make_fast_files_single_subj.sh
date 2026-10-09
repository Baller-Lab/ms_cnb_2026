#!/bin/bash
# Pre:  - called as one task of an LSF job array from get_fast_total_brain_volume_all_subjs.sh,
#         with $LSB_JOBINDEX set by LSF and args: SUB_SES_LIST DATA_DIR FAST_SUBDIR
#         (reads its own "empi,date" row at line $LSB_JOBINDEX of SUB_SES_LIST)
#       - Bias-corrected skull-stripped T1 exists at
#         $data_dir/sub-{empi}/ses-{date}/bias_correction/T1_brain_n4.nii.gz
#         (HD-BET-based for the 9 failed BET skull strips, regenerated 7/1/2026)
# Post: - ${fast_subdir}/ directory created at $data_dir/sub-{empi}/ses-{date}/
#       - FSL FAST segmentation files written there
#       - total_fast_brain_volume_values.csv written there with columns:
#         EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume,fast_icv
# Uses: Runs FSL FAST on the bias-corrected skull-stripped T1 and extracts
#       PARTIAL-VOLUME-WEIGHTED tissue volumes: for each pve map,
#       fslstats -M -V gives the mean pve of nonzero voxels and their volume, and
#       mean x volume = sum of the pve values x voxel size = the tissue volume.
#       (The first run used fslstats -V alone, which counts every voxel with ANY
#       probability of that tissue as a full voxel -> overcounts every tissue.)
#       To test one subject by hand: LSB_JOBINDEX=1 ./make_fast_files_single_subj.sh one_subject_list.csv <data_dir> fast_hdbet
# Dependencies: FSL

set -euf -o pipefail

# FSL module (same one the mimosa scripts load) -- module scripts can reference unset
# variables, which set -u would turn into errors, so wrap it
fsl_module="fsl/6.0.3"
set +u; module load "${fsl_module}" 2>/dev/null || echo "NOTE: could not module load ${fsl_module}; using whatever fast/fslstats is on PATH"; set -u
echo "Using fast: $(command -v fast)"

if [ $# -lt 3 ]; then
    echo "Usage: $0 SUB_SES_LIST DATA_DIR FAST_SUBDIR   (run as an LSF array task, or with LSB_JOBINDEX set by hand)"
    exit 1
fi
sub_ses_list=$1
data_dir=$2
fast_subdir=$3

if [ -z "${LSB_JOBINDEX:-}" ]; then
    echo "ERROR: LSB_JOBINDEX is not set -- run as an LSF array task, or set it by hand for one subject" >&2
    exit 1
fi

#pull this task's row out of the shared list -- LSB_JOBINDEX is 1-based, same as sed -n Np
row=$(sed -n "${LSB_JOBINDEX}p" "${sub_ses_list}")
if [ -z "${row}" ]; then
    echo "ERROR: no row at line ${LSB_JOBINDEX} of ${sub_ses_list}" >&2
    exit 1
fi
sub=$(echo "${row}" | cut -d, -f1)
ses=$(echo "${row}" | cut -d, -f2)

export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${LSB_DJOB_NUMPROC:-1}

subj_dir="${data_dir}/sub-${sub}/ses-${ses}"
t1_input="${subj_dir}/bias_correction/T1_brain_n4.nii.gz"
fast_dir="${subj_dir}/${fast_subdir}"
output_prefix="${fast_dir}/fast"
output_csv="${fast_dir}/total_fast_brain_volume_values.csv"

#fallback (10/9/2026): subjects with no usable FLAIR can't go through MIMOSA, so they have no
#bias_correction/T1_brain_n4. For them, use the HD-BET skull-stripped T1 (t1_brain/brain.nii.gz,
#from run_hdbet_skullstripping). It isn't N4-corrected, but FAST estimates its own bias field
#(-t 1 ... -l 20.0 below), so the difference is small. Only 1 subject as of 10/9/2026.
if [ ! -f "${t1_input}" ] && [ -f "${subj_dir}/t1_brain/brain.nii.gz" ]; then
    echo "NOTE: no ${t1_input} (no MIMOSA run) -- using the HD-BET brain ${subj_dir}/t1_brain/brain.nii.gz instead"
    t1_input="${subj_dir}/t1_brain/brain.nii.gz"
fi

if [ ! -f "${t1_input}" ]; then
    echo "ERROR: ${t1_input} not found for sub-${sub} ses-${ses} (and no t1_brain/brain.nii.gz either)" >&2
    exit 1
fi

#diagnostic: if this subject has an HD-BET t1_brain/, show both timestamps so it's easy to
#confirm the N4 brain FAST is about to use was made AFTER the HD-BET skull strip
echo "FAST input: ${t1_input} ($(date -r "${t1_input}" '+%Y-%m-%d %H:%M'))"
if [ -f "${subj_dir}/t1_brain/brain.nii.gz" ]; then
    echo "  HD-BET brain: ${subj_dir}/t1_brain/brain.nii.gz ($(date -r "${subj_dir}/t1_brain/brain.nii.gz" '+%Y-%m-%d %H:%M'))"
    if [ "${t1_input}" -ot "${subj_dir}/t1_brain/brain.nii.gz" ]; then
        echo "  WARNING: T1_brain_n4 is OLDER than the HD-BET brain -- it may still be the failed BET brain" >&2
    fi
fi

mkdir -p "${fast_dir}"
echo "Running FAST for sub-${sub} ses-${ses} -> ${fast_dir} ..."

# Run FAST (same settings as the first run)
fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -o "${output_prefix}" "${t1_input}"

# partial-volume-weighted volume of one pve map: fslstats -M -V prints
# "<mean of nonzero voxels> <n nonzero voxels> <volume of nonzero voxels in mm3>",
# and mean x volume = the pve-weighted tissue volume in mm3
pve_volume() { fslstats "$1" -M -V | awk '{ printf "%.4f", $1 * $3 }'; }

csf_vol=$(pve_volume "${output_prefix}_pve_0.nii.gz")
gm_vol=$(pve_volume "${output_prefix}_pve_1.nii.gz")
wm_vol=$(pve_volume "${output_prefix}_pve_2.nii.gz")
total_volume=$(awk -v g="${gm_vol}" -v w="${wm_vol}" 'BEGIN { printf "%.4f", g + w }')
#csf + gm + wm inside the brain mask -- NOT a true ICV (the mask excludes much of the CSF
#between brain and skull); kept only for comparison with the old intracranial_volume
fast_icv=$(awk -v c="${csf_vol}" -v g="${gm_vol}" -v w="${wm_vol}" 'BEGIN { printf "%.4f", c + g + w }')

echo "CSF: ${csf_vol}  GM: ${gm_vol}  WM: ${wm_vol}  Total (GM+WM): ${total_volume}  CSF+GM+WM: ${fast_icv}"

# Write per-subject CSV (the assembly job collects these)
rm -f "${output_csv}"
echo "EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume,fast_icv" > "${output_csv}"
echo "${sub},${ses},${csf_vol},${gm_vol},${wm_vol},${total_volume},${fast_icv}" >> "${output_csv}"

echo "Completed FAST for sub-${sub} ses-${ses}."
