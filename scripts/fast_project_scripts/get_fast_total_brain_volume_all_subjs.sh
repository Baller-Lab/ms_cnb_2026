#!/bin/bash
# Pre:  - run_mimosa.sh has been run successfully
#       - Bias-corrected skull-stripped T1 exists per subject at
#         $data_dir/sub-{empi}/ses-{date}/bias_correction/T1_brain_n4.nii.gz
#         (for the 9 subjects whose BET skull strip failed, this file was regenerated
#         from the HD-BET brain by the 7/1/2026 mimosa rerun -- checked 10/8/2026:
#         T1_brain_n4 15:15 is newer than t1_brain/ 12:34)
#       - sub_ses_list.csv contains one empi,date pair per line (no header)
# Post: - fast_hdbet/ directory created per subject with FSL FAST segmentation files
#         and total_fast_brain_volume_values.csv (written by make_fast_files_single_subj.sh)
#       - once every subject's job has ended, a dependent job assembles
#         ${results_dir}/total_fast_brain_volumes_hdbet_n<N>.csv (make_fast_volume_csv.sh)
# Uses: 10/8/2026 rerun of FAST, because the first run (6/24/2026) used the failed BET
#       skull strips for 9 subjects (implausible volumes) and computed volumes with
#       fslstats -V (counts every voxel with ANY tissue probability -> overcounts).
#       Submits the cohort as ONE LSF job array (one task per row of the subject list),
#       then a dependent assembly job -- same pattern as the openmap/samseg wrappers,
#       so the assembly reliably waits for every subject.
#       Writes to fast_hdbet/ and a new master file, so the old fast/ results and
#       total_fast_brain_volumes_n104.csv are left untouched for comparison.
# Dependencies: LSF (bsub), FSL

set -euf -o pipefail

#set up global variables
num_cores=1
mem_mb=8000

# ---- base paths: edit these, everything below is built from them --------------
base_dir="/project/msdepression"
data_dir="${base_dir}/data/radiology_pulls_20260610/data"
sub_ses_list="${data_dir}/other_data/cubids/sub_ses_list.csv"    # used only if you don't pass one as $1
scripts_dir="${base_dir}/scripts/fast_project_scripts"   # where the 3 FAST scripts live
results_dir="${base_dir}/results"

# per-subject output folder name (inside sub-*/ses-*/) and master-file prefix --
# both new for the rerun so nothing from the first FAST run is overwritten
fast_subdir="fast_hdbet"
outfile_prefix="total_fast_brain_volumes_hdbet"

max_concurrent=100
# --------------------------------------------------------------------------------

log_dir="${scripts_dir}/logfiles"
mkdir -p "${log_dir}" "${results_dir}"

if [ $# == 0 ]
then
    echo "We will use the default subject/session list: "$sub_ses_list
else
    sub_ses_list=$1
fi
echo "File being read is "$sub_ses_list

n_subjects=$(grep -c . "${sub_ses_list}")
echo "Found ${n_subjects} subject/session rows."

#timestamp -> unique job name, so the assembly only waits on THIS run
run_date=$(date +%Y%m%d_%H%M%S)
job_name="fast_hdbet_${run_date}"

#one array task per row; make_fast_files_single_subj.sh reads its row via $LSB_JOBINDEX
echo "... Submitting FAST job array (${n_subjects} tasks, ${max_concurrent} at a time) ..."
bsub -J "${job_name}[1-${n_subjects}]%${max_concurrent}" -n ${num_cores} \
    -R "rusage[mem=${mem_mb}]" \
    -o "${log_dir}/out_${job_name}_%I.out" \
    -e "${log_dir}/err_${job_name}_%I.err" \
    "${scripts_dir}/make_fast_files_single_subj.sh" "${sub_ses_list}" "${data_dir}" "${fast_subdir}"

master_csv="${results_dir}/${outfile_prefix}_n${n_subjects}.csv"

#assembly waits on the whole array by its base name
echo "... Submitting assembly job (runs once every FAST task has ended) ..."
bsub -J "${job_name}_assemble" -n 1 \
    -w "ended(${job_name})" \
    -o "${log_dir}/out_${job_name}_assemble.out" \
    -e "${log_dir}/err_${job_name}_assemble.err" \
    "${scripts_dir}/make_fast_volume_csv.sh" "${sub_ses_list}" "${data_dir}" "${fast_subdir}" "${master_csv}"

echo "Submitted array ${job_name}[1-${n_subjects}] plus a dependent assembly job (${job_name}_assemble)."
echo "Results will land at:"
echo "  ${master_csv}"
