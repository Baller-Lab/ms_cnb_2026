SAMSEG ICV pipeline -- one-time setup on PMACS (LPC)
=====================================================
Scripts live in /project/msdepression/scripts/samseg_project_scripts/
(samseg_wrapper.sh, indiv_samseg_script.sh, assemble_samseg_volumes.sh)

Why a container: `pip install samseg` (the standalone package) failed on the LPC
with "IncompleteRead" at the same byte count every time (10/7/2026). Per Steven
Meisler's suggestion, use the FreeSurfer container, which includes run_samseg.

0) Copy this folder to the cluster, e.g. (run on your own computer):
     scp -r samseg_project_scripts <user>@<cluster>:/project/msdepression/scripts/

1) Make the scripts executable
     chmod +x /project/msdepression/scripts/samseg_project_scripts/*.sh

2) Build the FreeSurfer container (big: ~10 GB image, needs ~20+ GB of temp space).
   Apptainer's temp/cache default to $HOME or /tmp, which are too small on the LPC,
   so point them at /project. Run it as a job, not on the login node:

     mkdir -p /project/msdepression/scripts/samseg_project_scripts/containers/apptainer_tmp
     mkdir -p /project/msdepression/scripts/samseg_project_scripts/containers/apptainer_cache

     bsub -J build_fs -n 4 -R "rusage[mem=16000]" \
       -o /project/msdepression/scripts/samseg_project_scripts/containers/build_fs.out \
       -e /project/msdepression/scripts/samseg_project_scripts/containers/build_fs.err \
       "module load apptainer; \
        export APPTAINER_TMPDIR=/project/msdepression/scripts/samseg_project_scripts/containers/apptainer_tmp; \
        export APPTAINER_CACHEDIR=/project/msdepression/scripts/samseg_project_scripts/containers/apptainer_cache; \
        export SINGULARITY_TMPDIR=\$APPTAINER_TMPDIR SINGULARITY_CACHEDIR=\$APPTAINER_CACHEDIR; \
        apptainer pull /project/msdepression/scripts/samseg_project_scripts/containers/freesurfer_7.4.1.sif docker://freesurfer/freesurfer:7.4.1"

   (if `module load apptainer` fails, try `module load singularity` and use `singularity pull`;
    then also change `module load apptainer` / `apptainer exec` in indiv_samseg_script.sh)

   Check it worked:
     ls -lh /project/msdepression/scripts/samseg_project_scripts/containers/freesurfer_7.4.1.sif
     tail build_fs.err build_fs.out
   Once the .sif exists, the apptainer_tmp/ and apptainer_cache/ folders can be deleted.

3) FreeSurfer license: PMACS site license from their FreeSurfer 7.4.0 install:
     /appl/freesurfer-7.4.0/license.txt
   (the freesurfer/8.2.0 module points at /appl/freesurfer-8.2.0/.license/license.txt, which
   does not exist). indiv_samseg_script.sh points there (fs_license) and binds its folder into
   the container. No registration needed.

4) Quick check that SAMSEG runs inside the container:
     module load apptainer
     apptainer exec -B /project -B /appl/freesurfer-7.4.0 --env FS_LICENSE=/appl/freesurfer-7.4.0/license.txt /project/msdepression/scripts/samseg_project_scripts/containers/freesurfer_7.4.1.sif run_samseg --help

5) Test one subject (T1 run), then run everyone -- see the commands in samseg_wrapper.sh's header:
     cd /project/msdepression/scripts/samseg_project_scripts
     grep "^<EMPI>," /project/msdepression/data/radiology_pulls_20260610/data/other_data/cubids/sub_ses_list.csv > one_subject_list.csv
     bsub -J samseg_test -n 4 -R "rusage[mem=16000] span[hosts=1]" -o samseg_test.out -e samseg_test.err "LSB_JOBINDEX=1 ./indiv_samseg_script.sh one_subject_list.csv 0"
     grep -i "SAMSEG\|ICV\|Parsed\|ERROR\|WARNING" samseg_test.out samseg_test.err
     ./samseg_wrapper.sh
