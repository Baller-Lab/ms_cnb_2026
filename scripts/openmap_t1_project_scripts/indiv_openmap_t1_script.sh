#!/bin/bash

### Runs OpenMAP-T1 parcellation for a single subject/session and extracts
### per-subject thalamus + whole-brain volume CSVs.
### Pre: called as one task of an LSF job array (see openmap_t1_wrapper.sh),
###      with $LSB_JOBINDEX set by LSF and SUB_SES_LIST as $1. Reads its own
###      "sub_id,ses_id" row at line $LSB_JOBINDEX of SUB_SES_LIST.
###      data_dir/sub-<sub_id>/ses-<ses_id> must contain anat/*T1*.nii.gz
### Post: subj_dir/openmap-t1/{input,output}/ populated with the parcellation
###       run; subj_dir/openmap-t1/thalamic_volume.csv and all_volumes.csv
###       written for the wrapper's assembly step to pick up later.
### Uses: MS depression project -- per-subject step, called by bsub from
###       openmap_t1_wrapper.sh as an array task. To sanity-check on one
###       subject by hand before running the whole cohort, set LSB_JOBINDEX=1
###       yourself against a one-row sub_ses_list.csv, e.g.:
###         LSB_JOBINDEX=1 ./indiv_openmap_t1_script.sh one_subject_list.csv
set -euf -o pipefail

# ---- base paths: edit these, everything below is built from them ----------
base_dir="/project/msdepression"
data_dir="/project/msdepression/data/radiology_pulls_20260610/data"
openmapt1_dir="${base_dir}/scripts/OpenMAP-T1"
model_dir="${openmapt1_dir}/models/OpenMAP-T1-V3.0.0/"     # edit if CNet/SSNet/PNet/HNet weights live elsewhere

# base region name for the thalamus csv -- change this one variable and every
# thalamus column (Thalamus_L, Thalamus_R, Thalamus_total) renames with it.
# Capitalized to match OpenMAP-T1's own Name_L/Name_R naming convention
# (confirmed against real output: header columns are "Thalamus_L" /
# "Thalamus_R", same suffix pattern as every other region, e.g. SFG_L/SFG_R).
thal_prefix="Thalamus"
# --------------------------------------------------------------------------

if [ $# -lt 1 ]
then
    echo "You did not enter a sub_ses_list path. Make sure your call makes sense"
    echo "Usage: $0 SUB_SES_LIST   (run as an LSF array task, or with LSB_JOBINDEX set by hand)"
    exit 1
fi
sub_ses_list=$1

if [ -z "${LSB_JOBINDEX:-}" ]; then
    echo "ERROR: LSB_JOBINDEX is not set. This script expects to run as one task of an LSF" >&2
    echo "       job array (see openmap_t1_wrapper.sh). For a single-subject test, set it by" >&2
    echo "       hand, e.g.: LSB_JOBINDEX=1 $0 ${sub_ses_list}" >&2
    exit 1
fi

#pull this task's row out of the shared list -- LSB_JOBINDEX is 1-based, same as sed's -n Np
row=$(sed -n "${LSB_JOBINDEX}p" "${sub_ses_list}")
if [ -z "${row}" ]; then
    echo "ERROR: no row at line ${LSB_JOBINDEX} of ${sub_ses_list}" >&2
    exit 1
fi
subject_id=$(echo "${row}" | cut -d, -f1)
session_id=$(echo "${row}" | cut -d, -f2)
echo "Array task ${LSB_JOBINDEX}: sub-${subject_id} ses-${session_id} ..."

#build this subject/session's data directory from data_dir + the two IDs --
#ASSUMES on-disk folders are named sub-<ID>/ses-<ID> (same convention already
#used in the mimosa tractography scripts). If this is wrong, the find below
#fails loudly with the exact path it tried, so it's easy to catch on the
#single-subject test run.
subj_dir="${data_dir}/sub-${subject_id}/ses-${session_id}"
echo "Subject directory is ${subj_dir}"

#find the T1/MPRAGE inside this subject's anat folder -- head -n1 in case more
#than one file matches (e.g. a defaced copy sitting alongside the original)
t1_file=$(find "${subj_dir}/anat" -maxdepth 1 -iname "*T1*.nii.gz" 2>/dev/null | head -n1)
if [ -z "${t1_file}" ]; then
    echo "ERROR: no anat/*T1*.nii.gz found under ${subj_dir}" >&2
    exit 1
fi
echo "T1 file is ${t1_file}"

#build this subject's openmap-t1 working directory: input/ holds a symlink to
#just this one T1 (OpenMAP-T1 treats every file dropped in the input folder as
#a case to process, so each subject needs its own isolated input folder),
#output/ is where parcellation.py writes everything
openmap_dir="${subj_dir}/openmap-t1"
in_dir="${openmap_dir}/input"
out_dir="${openmap_dir}/output"
mkdir -p "${in_dir}" "${out_dir}"
ln -sf "${t1_file}" "${in_dir}/$(basename "${t1_file}")"

# ---- figure out how to invoke this repo's python -------------------------
#prefer the repo's own uv-managed env; fall back to a plain .venv; last resort
#is whatever python3 is on $PATH (likely to be missing torch/pandas -- if you
#hit an import error here, hardcode PYCMD to your actual env's python instead)
cd "${openmapt1_dir}"
if command -v uv >/dev/null 2>&1 && [ -f "pyproject.toml" ]; then
    echo "Using: uv run python"
    PYCMD="uv run python"
elif [ -x "${openmapt1_dir}/.venv/bin/python3" ]; then
    echo "Using repo .venv"
    PYCMD="${openmapt1_dir}/.venv/bin/python3"
else
    echo "WARNING: could not detect uv or .venv in ${openmapt1_dir}; falling back to system python3." >&2
    echo "         If parcellation.py fails to import torch/pandas/etc, fix PYCMD/env activation" >&2
    echo "         at the top of $0." >&2
    PYCMD="python3"
fi

#fail loudly and immediately if the model weights aren't where we expect,
#rather than letting parcellation.py die deeper in with a confusing error
if [ ! -d "${model_dir}" ]; then
    echo "ERROR: model_dir (${model_dir}) not found. Edit model_dir at the top of $0 to point" >&2
    echo "       at the folder containing CNet/, SSNet/, PNet/, HNet/ weights." >&2
    exit 1
fi

#keep pytorch's CPU thread pool in line with the cores this bsub job actually got
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

#the actual parcellation run
${PYCMD} src/parcellation.py -i "${in_dir}" -o "${out_dir}" -m "${model_dir}"

# ---- locate the finest-level (280-region, named) output CSV --------------
#OpenMAP-T1 names its output case folder after the input filename minus extension
case_name=$(basename "${t1_file}" | perl -pe 's/\.nii(\.gz)?$//')
case_csv_dir="${out_dir}/${case_name}/csv"

#prefer the Type1 Level5 csv (cortex + subcortical white matter kept separate,
#all 280 named regions); fall back to any Level5 csv if the Type1 tag isn't there
level5_csv=$(find "${case_csv_dir}" -iname "*Type1*Level5*.csv" 2>/dev/null | head -n1)
if [ -z "${level5_csv}" ]; then
    level5_csv=$(find "${case_csv_dir}" -iname "*Level5*.csv" 2>/dev/null | head -n1)
fi
if [ -z "${level5_csv}" ]; then
    echo "ERROR: could not find a Level5 region-volume CSV under ${case_csv_dir}" >&2
    echo "       Contents of ${out_dir}:" >&2
    find "${out_dir}" -maxdepth 4 >&2 || true
    exit 1
fi
echo "Region CSV is ${level5_csv}"

#per-subject output files -- the wrapper's assembly step reads these later,
#it never has multiple subjects writing into the same file at once
thal_out="${openmap_dir}/thalamic_volume.csv"
allvol_out="${openmap_dir}/all_volumes.csv"

#CONFIRMED format (checked against real output on 2026-08-07): each
#Type1_Level5 csv is exactly 2 lines -- a header of ~280 region-name columns
#(e.g. "...,Thalamus_L,Thalamus_R,..."), then one data line with that
#subject's volumes in the same column order. It's already wide, not a
#name,volume-per-row table.
echo "Region CSV has $(head -n1 "${level5_csv}" | awk -F',' '{print NF}') header columns and $(wc -l < "${level5_csv}") lines total (expect 2: header + 1 data row)"

#--- all_volumes.csv: source file is already wide, so this is just that file
#with subject,session prepended to both the header and the one data line --
#no pivot needed.
{
    echo "EMPI,EXAM_DATE,$(head -n1 "${level5_csv}")"
    echo "${subject_id},${session_id},$(sed -n '2p' "${level5_csv}")"
} > "${allvol_out}"

#--- thalamic_volume.csv: region names are column headers here, not row
#values, so find Thalamus_L/Thalamus_R's column position from the header
#line, then pull that same position out of the one data line. Suffix order
#(Name_L/Name_R) confirmed against real output -- matches every other region
#in the atlas (SFG_L, SFG_R, MFG_L, MFG_R, ...), not a L_Name prefix.
read -r l_vol r_vol <<< "$(awk -F',' -v target_l="${thal_prefix}_L" -v target_r="${thal_prefix}_R" '
    NR==1 {
        for (i=1; i<=NF; i++) {
            if ($i == target_l) l_idx = i
            if ($i == target_r) r_idx = i
        }
        next
    }
    NR==2 {
        print (l_idx ? $(l_idx) : "NA"), (r_idx ? $(r_idx) : "NA")
    }
' "${level5_csv}")"
l_vol="${l_vol:-NA}"
r_vol="${r_vol:-NA}"

#sanity check: how many header columns mention "thalamus" at all, case-
#insensitive. If this isn't 2, the atlas may split the thalamus into more
#sub-regions than just Thalamus_L/Thalamus_R and we're missing volume.
n_thal_cols=$(head -n1 "${level5_csv}" | tr ',' '\n' | grep -ic thalamus || true)
echo "Header columns containing 'thalamus' (any case) in ${level5_csv}: ${n_thal_cols} (expect exactly 2: ${thal_prefix}_L, ${thal_prefix}_R)"

if [ "${l_vol}" = "NA" ] && [ "${r_vol}" = "NA" ]; then
    echo "WARNING: neither ${thal_prefix}_L nor ${thal_prefix}_R found as a column in ${level5_csv}" >&2
    total_vol="NA"
else
    l_num="${l_vol}"; [ "${l_num}" = "NA" ] && l_num=0
    r_num="${r_vol}"; [ "${r_num}" = "NA" ] && r_num=0
    #awk handles the add so we don't need bc
    total_vol=$(awk -v l="${l_num}" -v r="${r_num}" 'BEGIN{printf "%g", l+r}')
fi

echo "EMPI,EXAM_DATE,${thal_prefix}_L,${thal_prefix}_R,${thal_prefix}_total" > "${thal_out}"
echo "${subject_id},${session_id},${l_vol},${r_vol},${total_vol}" >> "${thal_out}"

echo "Done: ${subject_id} ${session_id}"
echo "  ${thal_out}"
echo "  ${allvol_out}"