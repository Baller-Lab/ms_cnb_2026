FAST tissue volumes -- /project/msdepression/scripts/fast_project_scripts
(moved here 10/9/2026 from scripts/elena_mimosa_project_scripts)

  get_fast_total_brain_volume_all_subjs.sh [SUB_SES_LIST]
     submits one LSF array task per subject (make_fast_files_single_subj.sh -> sub-*/ses-*/fast_hdbet/)
     plus a dependent assembly job (make_fast_volume_csv.sh -> results/total_fast_brain_volumes_hdbet_n<N>.csv)
  Input: bias_correction/T1_brain_n4.nii.gz (from MIMOSA); falls back to t1_brain/brain.nii.gz (HD-BET) for
  people with no MIMOSA run. Volumes are partial-volume weighted (fslstats -M -V). Logs in ./logfiles/
  One subject by hand: LSB_JOBINDEX=1 ./make_fast_files_single_subj.sh one_subject_list.csv <data_dir> fast_hdbet
