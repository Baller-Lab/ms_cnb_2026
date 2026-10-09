#!/bin/bash

### Runs FreeSurfer SAMSEG for a single subject/session and writes a per-subject
### CSV with intracranial volume (ICV) + every SAMSEG structure volume.
### Pre: called as one task of an LSF job array (see samseg_wrapper.sh), with
###      $LSB_JOBINDEX set by LSF, SUB_SES_LIST as $1, and USE_FLAIR (0/1) as $2
###      (set once in the wrapper; defaults to 0 if not given). Reads its own
###      "sub_id,ses_id" row at line $LSB_JOBINDEX of SUB_SES_LIST.
###      data_dir/sub-<sub_id>/ses-<ses_id>/anat/ must contain *_T1w.nii.gz
###      (and *_FLAIR.nii.gz for the FLAIR run).
### Post: T1-only run  (USE_FLAIR=0) -> subj_dir/samseg/
###       FLAIR run    (USE_FLAIR=1) -> subj_dir/samseg_flair/
###       Each holds the SAMSEG run (seg.mgz, samseg.stats, sbtiv.stats, ...) plus
###       samseg_volumes.csv for the wrapper's assembly step:
###         EMPI,EXAM_DATE,samseg_icv,<one column per SAMSEG structure>
###       The two runs never overwrite each other, so both can exist side by side
###       (T1-only for ICV in everyone, FLAIR for lesion-aware GM/WM).
###       In the FLAIR run, subjects with no FLAIR (or listed in no_flair_ids)
###       are SKIPPED, not run T1-only -- so every FLAIR-run volume comes from
###       the same method; they get NA rows at assembly.
### Uses: MS depression / CNB project -- per-subject step, called by bsub from
###       samseg_wrapper.sh. To test on ONE subject by hand first (recommended --
###       check the log for the stats-file printout and the ICV line):
###         LSB_JOBINDEX=1 ./indiv_samseg_script.sh one_subject_list.csv 0
### Dependencies: run_samseg -- by default the stand-alone SAMSEG python package
###               (pip install samseg; no FreeSurfer install or license), or full
###               FreeSurfer via module/apptainer (see samseg_mode below);
###               FSL (flirt) for the FLAIR -> T1 registration if use_flair=1
set -euf -o pipefail

# ---- base paths / settings: edit these, everything below is built from them ----
base_dir="/project/msdepression"
data_dir="/project/msdepression/data/radiology_pulls_20260610/data"

# how to get run_samseg on PMACS -- "standalone" (default), "module", or "container"
#   standalone: the stand-alone SAMSEG python package (no FreeSurfer install, no
#               FreeSurfer license). One-time setup on PMACS:
#                 python3 -m venv ${samseg_venv}
#                 ${samseg_venv}/bin/pip install samseg
#   module:     module load ${fs_module}  (only if PMACS has FreeSurfer >= 7)
#   container:  apptainer exec on ${fs_sif} (full FreeSurfer image)
#   module/container are full FreeSurfer, which needs ${fs_license}
samseg_mode="container"      # 10/8/2026: pip install of standalone samseg kept failing on the LPC (IncompleteRead), so using the FreeSurfer container
samseg_venv="${base_dir}/scripts/samseg_project_scripts/samseg_env"
fs_module="freesurfer/7.4.1"
fs_sif="${base_dir}/scripts/samseg_project_scripts/containers/freesurfer_7.4.1.sif"   # built with apptainer pull, see README_install.txt
# FreeSurfer license -- PMACS site license from their FreeSurfer 7.4.0 install (root-owned, world-
# readable; checked 10/8/2026). The freesurfer/8.2.0 module points FS_LICENSE at
# /appl/freesurfer-8.2.0/.license/license.txt, but that file does not exist. Licenses aren't
# version-specific, so this works for the 7.4.1 container. module/container only
fs_license="/appl/freesurfer-7.4.0/license.txt"

# FSL is used to register the FLAIR to the T1 (FLIRT, rigid 6 dof) -- same module
# the mimosa scripts load
fsl_module="fsl/6.0.3"

# EMPIs whose FLAIR should NOT be used (e.g. a bad-quality FLAIR -- the same person
# MIMOSA couldn't segment). Space-separated, e.g. no_flair_ids="1234567890 2345678901".
# Only matters for the FLAIR run; they still get ICV from the T1-only run.
no_flair_ids=""
# --------------------------------------------------------------------------

if [ $# -lt 1 ]
then
    echo "You did not enter a sub_ses_list path. Make sure your call makes sense"
    echo "Usage: $0 SUB_SES_LIST [USE_FLAIR 0|1]   (run as an LSF array task, or with LSB_JOBINDEX set by hand)"
    exit 1
fi
sub_ses_list=$1

# use_flair=0 -> T1 only: no registration, no FSL. All we need for ICV, which is
#                essentially the same with or without the FLAIR.
# use_flair=1 -> multi-contrast SAMSEG with the MS lesion model (T1 + FLAIR, --lesion):
#                better GM/WM in MS (lesions aren't called GM). The FLAIR is rigidly
#                registered to the T1 first (FSL FLIRT), since SAMSEG needs its inputs aligned.
use_flair=${2:-0}
if [ "${use_flair}" != 0 ] && [ "${use_flair}" != 1 ]; then
    echo "ERROR: USE_FLAIR (\$2) must be 0 or 1, got '${use_flair}'" >&2
    exit 1
fi
#each run gets its own folder so the two never overwrite each other
if [ "${use_flair}" == 1 ]; then samseg_subdir="samseg_flair"; else samseg_subdir="samseg"; fi

if [ -z "${LSB_JOBINDEX:-}" ]; then
    echo "ERROR: LSB_JOBINDEX is not set. This script expects to run as one task of an LSF" >&2
    echo "       job array (see samseg_wrapper.sh). For a single-subject test, set it by" >&2
    echo "       hand, e.g.: LSB_JOBINDEX=1 $0 ${sub_ses_list}" >&2
    exit 1
fi

#pull this task's row out of the shared list -- LSB_JOBINDEX is 1-based, same as sed -n Np
row=$(sed -n "${LSB_JOBINDEX}p" "${sub_ses_list}")
if [ -z "${row}" ]; then
    echo "ERROR: no row at line ${LSB_JOBINDEX} of ${sub_ses_list}" >&2
    exit 1
fi
subject_id=$(echo "${row}" | cut -d, -f1)
session_id=$(echo "${row}" | cut -d, -f2)
echo "Array task ${LSB_JOBINDEX}: sub-${subject_id} ses-${session_id} ..."

#this subject's directories, built from data_dir + the two IDs
subj_dir="${data_dir}/sub-${subject_id}/ses-${session_id}"
samseg_dir="${subj_dir}/${samseg_subdir}"
reg_dir="${samseg_dir}/flair_to_t1"
out_csv="${samseg_dir}/samseg_volumes.csv"
echo "Subject directory is ${subj_dir}; SAMSEG output -> ${samseg_dir} (use_flair=${use_flair})"

#find the raw T1w (and FLAIR) by suffix, like the mimosa scripts -- some filenames have
#mismatched sub IDs from cuBIDS (folder = ground truth). Uses find, not ls with a *
#wildcard: set -f above turns wildcard expansion off, so ls *_T1w.nii.gz would never match
t1_file=$(find "${subj_dir}/anat" -maxdepth 1 -name "*_T1w.nii.gz" 2>/dev/null | sort | head -n1 || true)
if [ -z "${t1_file}" ]; then
    echo "ERROR: no anat/*_T1w.nii.gz found under ${subj_dir}" >&2
    exit 1
fi
echo "T1 file is ${t1_file}"

#FLAIR run: skip (don't fall back to T1-only) anyone with no usable FLAIR, so every
#volume in the FLAIR-run master file comes from the same method. exit 0 = nothing went
#wrong; the assembly step writes them an NA row. Their ICV comes from the T1-only run.
if [ "${use_flair}" == 1 ]; then
    if [[ " ${no_flair_ids} " == *" ${subject_id} "* ]]; then
        echo "sub-${subject_id} is in no_flair_ids -- skipping the FLAIR run for this subject (NA at assembly)"
        exit 0
    fi
    flair_file=$(find "${subj_dir}/anat" -maxdepth 1 -name "*_FLAIR.nii.gz" 2>/dev/null | sort | head -n1 || true)
    if [ -z "${flair_file}" ]; then
        echo "No anat/*_FLAIR.nii.gz for sub-${subject_id} -- skipping the FLAIR run for this subject (NA at assembly)"
        exit 0
    fi
    echo "FLAIR file is ${flair_file}"
fi
mkdir -p "${samseg_dir}"

# ---- set up SAMSEG: SAMSEG() runs run_samseg the same way whichever mode is
#      chosen, so the rest of the script doesn't care ----
threads=${LSB_DJOB_NUMPROC:-1}
#module scripts often reference unset variables, which set -u would turn into errors,
#so every module load below is wrapped in set +u / set -u
if [ "${samseg_mode}" == "standalone" ]; then
    if [ ! -x "${samseg_venv}/bin/run_samseg" ]; then
        echo "ERROR: ${samseg_venv}/bin/run_samseg not found. One-time setup on PMACS:" >&2
        echo "         python3 -m venv ${samseg_venv} && ${samseg_venv}/bin/pip install samseg" >&2
        exit 1
    fi
    SAMSEG() { "${samseg_venv}/bin/run_samseg" "$@"; }
    #diagnostic: which samseg version we got (check this in the log on the first test)
    echo "SAMSEG (standalone) version: $("${samseg_venv}/bin/pip" show samseg 2>/dev/null | grep -i '^version' || echo unknown)"
else
    #full FreeSurfer (module or container) refuses to run without a license file --
    #check up front so a missing license is a clear one-line error, not a crash inside SAMSEG
    if [ ! -f "${fs_license}" ]; then
        echo "ERROR: FreeSurfer license not found at ${fs_license}" >&2
        echo "       Get one (free) at https://surfer.nmr.mgh.harvard.edu/registration.html" >&2
        exit 1
    fi
    if [ "${samseg_mode}" == "module" ]; then
        export FS_LICENSE="${fs_license}"
        set +u; module load "${fs_module}"; set -u
        SAMSEG() { run_samseg "$@"; }
        echo "SAMSEG from FreeSurfer module ${fs_module}: $(cat "${FREESURFER_HOME}/build-stamp.txt" 2>/dev/null || echo unknown)"
    else
        if [ ! -f "${fs_sif}" ]; then
            echo "ERROR: FreeSurfer container not found at ${fs_sif} -- build it first (see README_install.txt)" >&2
            exit 1
        fi
        set +u; module load apptainer; set -u
        #bind /project (data_dir) and the license's folder (it lives under /appl, outside /project)
        #so the container can see both
        SAMSEG() { apptainer exec -B /project -B "$(dirname "${fs_license}")" --env FS_LICENSE="${fs_license}" "${fs_sif}" run_samseg "$@"; }
        #diagnostic: FreeSurfer version inside the container (check this in the log on the first test)
        echo "SAMSEG from FreeSurfer container ${fs_sif}: $(apptainer exec "${fs_sif}" bash -c 'cat $FREESURFER_HOME/build-stamp.txt' 2>/dev/null || echo 'version unknown')"
    fi
fi

# ---- run SAMSEG ----
#SAMSEG prints a LOT (thousands of histogram lines per subject). Send all of it to a log
#file in the subject's folder on /project instead of through LSF -- with 50 jobs at once,
#LSF's copies of that output filled the home-directory quota on 10/8/2026 (Disk quota
#exceeded -> every job died ~6 min in). The log sits next to (not inside) the samseg
#folder in case run_samseg clears its output folder when it starts. The LSF log keeps
#just this script's short summary lines.
samseg_log="${subj_dir}/${samseg_subdir}_run_log.txt"
echo "SAMSEG output is being written to ${samseg_log}"
#on failure, show the end of that log in the LSF error file so the reason is easy to find
samseg_failed() { echo "ERROR: run_samseg failed for sub-${subject_id} ses-${session_id} -- last lines of ${samseg_log}:" >&2; tail -n 20 "${samseg_log}" >&2; exit 1; }

if [ "${use_flair}" == 1 ]; then
    #SAMSEG needs its input contrasts in the same space: rigidly register the FLAIR
    #to the T1 with FSL FLIRT (6 dof = rigid, same subject), writing the FLAIR
    #resampled onto the T1 grid
    set +u; module load "${fsl_module}"; set -u
    mkdir -p "${reg_dir}"
    flirt -in "${flair_file}" -ref "${t1_file}" -dof 6 \
          -omat "${reg_dir}/flair_to_t1.mat" -out "${reg_dir}/flair_in_t1.nii.gz"
    echo "FLAIR registered to T1 -> ${reg_dir}/flair_in_t1.nii.gz (check this overlay on the first test subject)"

    #multi-contrast SAMSEG with the MS lesion model. --lesion-mask-pattern 0 1 =
    #lesions are not constrained on the T1 and must be hyperintense on FLAIR
    #(the recommended setting for T1 + FLAIR in MS). The lesion model uses random sampling,
    #so a fixed --random-seed makes reruns give identical volumes
    SAMSEG --input "${t1_file}" "${reg_dir}/flair_in_t1.nii.gz" \
        --pallidum-separate --lesion --lesion-mask-pattern 0 1 --random-seed 12345 \
        --output "${samseg_dir}" --threads ${threads} > "${samseg_log}" 2>&1 || samseg_failed
else
    SAMSEG --input "${t1_file}" --output "${samseg_dir}" --threads ${threads} > "${samseg_log}" 2>&1 || samseg_failed
fi
echo "SAMSEG finished for sub-${subject_id} ses-${session_id}"

# ---- pull volumes out of the stats files ----
#SAMSEG writes one "# Measure <structure>, <volume>, mm^3" line per structure in
#samseg.stats, and the intracranial volume in sbtiv.stats ("# Measure Intra-Cranial, ...").
#diagnostic: print the raw files so the first run can be eyeballed -- if the format
#differs from the above, the perl below is the only thing to change
stats_file="${samseg_dir}/samseg.stats"
tiv_file="${samseg_dir}/sbtiv.stats"
for f in "${stats_file}" "${tiv_file}"; do
    if [ ! -f "${f}" ]; then
        echo "ERROR: expected ${f} was not written -- SAMSEG probably failed, see above" >&2
        exit 1
    fi
done
echo "---- head of ${stats_file} ----"; head -n 5 "${stats_file}"
echo "---- ${tiv_file} ----"; cat "${tiv_file}"

#ICV
samseg_icv=$(perl -ne 'print "$1\n" if /^#\s*Measure\s+Intra-Cranial\s*,\s*([0-9.eE+-]+)/' "${tiv_file}" | head -n1)
if [ -z "${samseg_icv}" ]; then
    echo "ERROR: could not find an Intra-Cranial line in ${tiv_file} -- check the printout above" >&2
    exit 1
fi
echo "SAMSEG ICV for sub-${subject_id} ses-${session_id}: ${samseg_icv} mm3"

#every structure, as "name,volume" lines -> wide (one header row of names, one data row)
#structure names get spaces/commas swapped for _ so they are safe as csv column names
perl -ne 'if (/^#\s*Measure\s+(.+?)\s*,\s*([0-9.eE+-]+)\s*,\s*mm\^3/) { ($n,$v)=($1,$2); $n =~ s/[ ,]+/_/g; print "$n,$v\n" }' "${stats_file}" > "${samseg_dir}/structure_volumes_long.csv"
n_structures=$(grep -c . "${samseg_dir}/structure_volumes_long.csv" || true)
echo "Parsed ${n_structures} structures from ${stats_file}"
if [ "${n_structures}" -eq 0 ]; then
    echo "ERROR: parsed 0 structures from ${stats_file} -- check the printout above" >&2
    exit 1
fi

struct_header=$(cut -d, -f1 "${samseg_dir}/structure_volumes_long.csv" | paste -sd, -)
struct_values=$(cut -d, -f2 "${samseg_dir}/structure_volumes_long.csv" | paste -sd, -)

#per-subject output -- the assembly step reads these later; never a shared file mid-run
rm -f "${out_csv}"
echo "EMPI,EXAM_DATE,samseg_icv,${struct_header}" > "${out_csv}"
echo "${subject_id},${session_id},${samseg_icv},${struct_values}" >> "${out_csv}"

echo "Done: ${subject_id} ${session_id} (use_flair=${use_flair})"
echo "  ${out_csv}"
