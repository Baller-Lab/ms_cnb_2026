# Imaging pipelines (PMACS LSF cluster)

Scripts that produced the 3T imaging measures for the MS CNB paper. They run on the PMACS cluster from
`/project/msdepression/scripts/<folder>/` (same folder names as here). Each folder has its own README with the run order.

| Folder | What it makes | Main scripts |
|---|---|---|
| `mimosa_project_scripts/` | HD-BET skull strip, MIMoSA white matter lesion maps, lesion count, lesion volume | `run_hdbet_skullstripping.sh` -> `run_mimosa.sh` -> `run_lesion_count.sh` -> `create_lesion_count_csv.sh`, `get_volume_of_mimosa_lesions.sh` |
| `samseg_project_scripts/` | SAMSEG (FreeSurfer 7.4.1 container): **ICV and thalamic volume used in the paper**, plus GM/WM | `samseg_wrapper.sh` -> `indiv_samseg_script.sh` (one LSF array task per scan) -> `assemble_samseg_volumes.sh` |
| `openmap_t1_project_scripts/` | OpenMAP-T1 parcellation (280 regions; thalamus + GM/WM totals, supplement) | `openmap_t1_wrapper.sh` -> `indiv_openmap_t1_script.sh` -> `assemble_openmap_t1_volumes.sh` |
| `fast_project_scripts/` | FSL FAST GM/WM/CSF (supplementary method comparison) | `get_fast_total_brain_volume_all_subjs.sh` (wrapper) -> `make_fast_files_single_subj.sh` (indiv) -> `make_fast_volume_csv.sh` (assemble) |

Every wrapper takes an optional subject list ("sub_id,ses_id" per line, no header) as its first argument and
otherwise uses the cohort list set at the top of the script, along with the base paths.

Order: HD-BET -> MIMoSA -> lesion count/volume and FAST (FAST uses MIMoSA's bias-corrected brain).
SAMSEG and OpenMAP-T1 only need the raw T1 and can run any time.

The master CSVs these write (in `/project/msdepression/results/`) are read by
`make_combined_spreadsheet_for_cnb_paper_post_replication_full_cnb_csv.Rmd`.

Subject lists, containers and data are on PMACS only and are not included here. Subject IDs in comments are placeholders.
