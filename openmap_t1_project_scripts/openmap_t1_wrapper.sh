#!/bin/bash

#### Welcome to the OpenMAP-T1 thalamic volume party #########
### Pre: Must have a sub_ses_list csv with one row per subject/session,
###      "sub_id,ses_id", no header (e.g. 8441811247,20230801). The
###      corresponding data_dir/sub-<sub_id>/ses-<ses_id> must contain
###      anat/*T1*.nii.gz
### Post: Each subject/session gets an openmap-t1/ subdir with the
###       parcellation output, plus two per-subject CSVs. Once every array
###       task has ended, a dependent aggregation job assembles the two master
###       CSVs under results_dir (per-subject writes only -- never concurrent
###       appends to a shared file, since that races when jobs run in parallel).
###       NOTE: the parcellation jobs are submitted as a single LSF job array
###       ("name[1-N]"), not N separately-named bsub calls -- that's what
###       makes "-w ended(name)" on the assembly job reliably wait for ALL of
###       them. A wildcard dependency across independently-named jobs
###       (ended(name_job*)) is NOT a guaranteed "wait for all" in LSF and was
###       observed firing the assembly job early.
### Uses: MS depression project -- whole-brain + thalamus volumes from T1
###       via OpenMAP-T1 deep-learning parcellation.
### Dependencies: OpenMAP-T1 installed at ${openmapt1_dir} (see below)
set -euf -o pipefail

#set up global variables
num_cores=1
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${num_cores}

# ---- base paths: edit these, everything below is built from them so you
#      only ever have to change a path in one place -------------------------
base_dir="/project/msdepression"
data_dir="/project/msdepression/data/radiology_pulls_20260610/data"                 # where subject data lives, one sub-<ID>/ses-<ID> dir per row of sub_ses_list
sub_ses_list="${data_dir}/other_data/cubids/sub_ses_list.csv"                       # sub_id,ses_id per line, no header -- used only if you don't pass one as $1
scripts_dir="${base_dir}/scripts/openmap_t1_project_scripts"                        # where these 3 scripts live (indiv + assemble called from here)
results_dir="${base_dir}/results"                                                   # where the 2 master CSVs land

# outfile basenames -- the actual filenames get "_n<num subjects>_from_openmap_t1.csv"
# appended further down, once we know how many subjects are in the list
thal_outfile_prefix="thalamic_volumes"
allvol_outfile_prefix="all_volumes"

# caps how many array tasks LSF will run at once (politeness to shared queues/
# fairshare, not a correctness requirement) -- set to n_subjects (or drop the
# %max_concurrent suffix below) to let them all run at once
max_concurrent=200
# --------------------------------------------------------------------------

#paths built from base_dir above -- no need to edit these directly
log_dir="${scripts_dir}/logfiles"
mkdir -p "${log_dir}" "${results_dir}"

if [ $# == 0 ]
then
    echo "We will use the default subject/session list: "$sub_ses_list
else
    sub_ses_list=$1
fi
echo "File being read is "$sub_ses_list

#count how many subject/session rows we have so it can go in the output filenames
n_subjects=$(grep -c . "${sub_ses_list}")
echo "Found ${n_subjects} subject/session rows."
echo "... Submitting parcellation jobs ..."

#timestamp used to build a unique array-job name, so this run's bsub -w
#dependency below only ever waits on THIS run's array, not anyone else's
run_date=$(date +%Y%m%d_%H%M%S)
job_name="openmapt1_${run_date}"

#submit the whole cohort as ONE LSF job array, one task per row of
#sub_ses_list.csv. indiv_openmap_t1_script.sh reads its own row via
#$LSB_JOBINDEX (set automatically per-task by LSF), so every task runs the
#exact same command line -- just the sub_ses_list path. %I in -o/-e is LSF's
#per-task placeholder, so each task gets its own log file.
echo "... Submitting parcellation job array (${n_subjects} tasks, ${max_concurrent} at a time) ..."
bsub -J "${job_name}[1-${n_subjects}]%${max_concurrent}" -n ${num_cores} \
    -o "${log_dir}/out_${job_name}_%I.out" \
    -e "${log_dir}/err_${job_name}_%I.err" \
    "${scripts_dir}/indiv_openmap_t1_script.sh" "${sub_ses_list}"

#build the final master-csv paths now that n_subjects is known
thal_master="${results_dir}/${thal_outfile_prefix}_n${n_subjects}_from_openmap_t1.csv"
allvol_master="${results_dir}/${allvol_outfile_prefix}_n${n_subjects}_from_openmap_t1.csv"

#submit the assembly job depending on the array by its base name (no [index])
#-- this is what LSF guarantees waits for every task in the array to end
#(success or fail), unlike a wildcard match across separately-named jobs
echo "... Submitting aggregation job (runs once every array task above has ended) ..."
bsub -J "${job_name}_assemble" -n 1 \
    -w "ended(${job_name})" \
    -o "${log_dir}/out_${job_name}_assemble.out" \
    -e "${log_dir}/err_${job_name}_assemble.err" \
    "${scripts_dir}/assemble_openmap_t1_volumes.sh" "${sub_ses_list}" "${thal_master}" "${allvol_master}"

echo "Submitted array ${job_name}[1-${n_subjects}] plus a dependent assembly job (${job_name}_assemble)."
echo "Results will land at:"
echo "  ${thal_master}"
echo "  ${allvol_master}"
