#!/bin/bash

#### Welcome to the SAMSEG intracranial volume party #########
### Pre: Must have a sub_ses_list csv with one row per subject/session,
###      "sub_id,ses_id", no header (e.g. 1234567890,20230101). The
###      corresponding data_dir/sub-<sub_id>/ses-<ses_id> must contain
###      anat/*_T1w.nii.gz (and anat/*_FLAIR.nii.gz if use_flair=1, set below).
###      run_samseg from the FreeSurfer 7.4.1 container (containers/freesurfer_7.4.1.sif)
###      with the PMACS site license -- see samseg_mode in indiv_samseg_script.sh and
###      README_install.txt (the stand-alone pip package would not install on the LPC).
### Post: Each subject/session gets a samseg/ subdir with the SAMSEG run, plus
###       a per-subject samseg_volumes.csv (EMPI, EXAM_DATE, samseg ICV, and
###       every SAMSEG structure volume). Once every array task has ended, a
###       dependent aggregation job assembles one master CSV under results_dir
###       (per-subject writes only -- never concurrent appends to a shared file).
###       NOTE: submitted as a single LSF job array ("name[1-N]") so that
###       "-w ended(name)" on the assembly job reliably waits for ALL tasks
###       (same reason as the OpenMAP-T1 wrapper).
### Uses: MS depression / CNB project -- a real intracranial volume (ICV) to
###       replace the FAST one, which failed for ~8 scans (ICV 0.25-2.5 million
###       mm3). SAMSEG works on the raw T1 (no separate skull strip needed), is
###       contrast-adaptive, and has an MS lesion mode, so the skull-strip
###       failures that broke FAST shouldn't matter here. Its ICV (sbTIV) is the
###       head-size covariate we want: it does not shrink with atrophy.
### Dependencies: LSF (bsub), apptainer + the FreeSurfer 7.4.1 container, FSL if use_flair=1
set -euf -o pipefail

#set up global variables -- SAMSEG is multi-threaded, so give each task a few
#cores; --threads in indiv_samseg_script.sh is set from LSB_DJOB_NUMPROC
num_cores=4
mem_mb=16000          # SAMSEG on a ~1 mm T1 typically needs well under this; lower once you see real usage in the logs

# ---- base paths: edit these, everything below is built from them so you
#      only ever have to change a path in one place -------------------------
base_dir="/project/msdepression"
data_dir="/project/msdepression/data/radiology_pulls_20260610/data"                 # one sub-<ID>/ses-<ID> dir per row of sub_ses_list
sub_ses_list="${data_dir}/other_data/cubids/sub_ses_list.csv"                       # sub_id,ses_id per line, no header -- used only if you don't pass one as $1
scripts_dir="${base_dir}/scripts/samseg_project_scripts"                            # where these 3 scripts live
results_dir="${base_dir}/results"                                                   # where the master CSV lands

# which run: 0 = T1 only (ICV for everyone -- run this one first), 1 = T1 + FLAIR with the
# MS lesion model (lesion-aware GM/WM; people without a usable FLAIR are skipped -> NA).
# The two runs write to different subject folders (samseg/ vs samseg_flair/) and
# different master files, so running both is safe.
use_flair=0

# outfile basename -- the actual filename gets "_n<num subjects>_from_samseg_<t1|t1flair>.csv" appended below
outfile_prefix="samseg_volumes"

# caps how many array tasks LSF runs at once (politeness to shared queues)
max_concurrent=50
# --------------------------------------------------------------------------

#paths built from base_dir above -- no need to edit these directly
if [ "${use_flair}" == 1 ]; then run_label="t1flair"; samseg_subdir="samseg_flair"; else run_label="t1"; samseg_subdir="samseg"; fi
log_dir="${scripts_dir}/logfiles"
mkdir -p "${log_dir}" "${results_dir}"

if [ $# == 0 ]
then
    echo "We will use the default subject/session list: "$sub_ses_list
else
    sub_ses_list=$1
fi
echo "File being read is "$sub_ses_list

#count how many subject/session rows we have so it can go in the output filename
n_subjects=$(grep -c . "${sub_ses_list}")
echo "Found ${n_subjects} subject/session rows."

#timestamp -> unique array-job name, so the -w dependency only waits on THIS run
run_date=$(date +%Y%m%d_%H%M%S)
job_name="samseg_${run_label}_${run_date}"

#submit the whole cohort as ONE LSF job array, one task per row of sub_ses_list.
#indiv_samseg_script.sh reads its own row via $LSB_JOBINDEX. %I in -o/-e gives
#each task its own log file. span[hosts=1] keeps all of a task's cores on one node.
echo "... Submitting SAMSEG job array (${run_label} run, ${n_subjects} tasks, ${max_concurrent} at a time) ..."
bsub -J "${job_name}[1-${n_subjects}]%${max_concurrent}" -n ${num_cores} \
    -R "rusage[mem=${mem_mb}] span[hosts=1]" \
    -o "${log_dir}/out_${job_name}_%I.out" \
    -e "${log_dir}/err_${job_name}_%I.err" \
    "${scripts_dir}/indiv_samseg_script.sh" "${sub_ses_list}" "${use_flair}"

#build the final master-csv path now that n_subjects is known
master_csv="${results_dir}/${outfile_prefix}_n${n_subjects}_from_samseg_${run_label}.csv"

#assembly job waits on the array by its base name (no [index]) -- LSF guarantees
#that waits for every task to end (success or fail)
echo "... Submitting aggregation job (runs once every array task above has ended) ..."
bsub -J "${job_name}_assemble" -n 1 \
    -w "ended(${job_name})" \
    -o "${log_dir}/out_${job_name}_assemble.out" \
    -e "${log_dir}/err_${job_name}_assemble.err" \
    "${scripts_dir}/assemble_samseg_volumes.sh" "${sub_ses_list}" "${master_csv}" "${samseg_subdir}"

echo "Submitted array ${job_name}[1-${n_subjects}] plus a dependent assembly job (${job_name}_assemble)."
echo "Results will land at:"
echo "  ${master_csv}"
