MIMoSA white matter lesion pipeline -- /project/msdepression/scripts/mimosa_project_scripts
Calls the PennSIVE neuro pipelines (PennSIVE_neuro_pip: skullstripping, mimosa, lesion_count), which run in
apptainer containers and submit one LSF job per scan.

Every script takes an optional subject list: one "sub_id,ses_id" pair per line, no header, e.g.
    1234567890,20230101
Without one, it uses the whole cohort list set near the top of the script (base paths are set there too).

Run order (wait for each step's jobs to finish before starting the next):
  1. ./run_hdbet_skullstripping.sh [LIST]        HD-BET skull strip -> sub-*/ses-*/t1_brain/brain.nii.gz + brain_mask.nii.gz
  2. ./run_mimosa.sh [LIST]                      MIMoSA on the HD-BET brain -> mimosa/mimosa_mask.nii.gz,
                                                 bias_correction/T1_brain_n4.nii.gz
                                                 (copies brain_mask.nii.gz -> brainmask.nii.gz first; MIMoSA only finds "brainmask")
  3. ./run_lesion_count.sh [LIST]                lesion count (connected components) -> count/*_connected_components.csv
  4. ./create_lesion_count_csv.sh                combines every count/ csv under the data folder -> results/lesion_count_n104.csv
  5. ./get_volume_of_mimosa_lesions.sh [LIST]    lesion volume (voxels in the MIMoSA mask) -> results/vol_mimosa_lesions/
                                                 (runs directly, no jobs; new timestamped file each run)
Logs from the PennSIVE pipelines: <project>/log/{output,error}/
FAST (fast_project_scripts) uses step 2's T1_brain_n4 (or the HD-BET brain if there is no MIMoSA run).
