#!/bin/bash

### Assembles per-subject OpenMAP-T1 CSVs (written by indiv_openmap_t1_script.sh)
### into the two project-wide master CSVs.
### Pre: every parcellation job in the cohort has ended (bsub -w "ended(...)"
###      dependency in the wrapper enforces this -- do not run by hand while
###      jobs are still in flight, since some subject files may still be
###      missing and would silently be skipped below).
### Post: THAL_MASTER_CSV and ALLVOL_MASTER_CSV written, exactly one row per
###       row of SUB_SES_LIST (same order, same count) -- missing/failed
###       subjects get an NA-filled row rather than being dropped, so the
###       master files always line up 1:1 with the subject list and don't
###       need a separate "who's missing" lookup before merging elsewhere.
### Uses: MS depression project -- final step of the OpenMAP-T1 pipeline,
###       called by bsub from openmap_t1_wrapper.sh once every per-subject job ends.
set -euf -o pipefail

# ---- base paths: must match indiv_openmap_t1_script.sh's copies, since we're
#      rebuilding the same subj_dir it wrote its per-subject csvs into ------
data_dir="/project/msdepression/data/radiology_pulls_20260610/data"

# must match thal_prefix in indiv_openmap_t1_script.sh, since that's what
# built the header row of every per-subject thalamic_volume.csv we're about
# to concatenate. Capitalized to match OpenMAP-T1's own L_/R_ naming
# convention (confirmed: "L_Thalamus" / "R_Thalamus").
thal_prefix="Thalamus"
# --------------------------------------------------------------------------

if [ $# -lt 3 ]; then
    echo "Usage: $0 SUB_SES_LIST THAL_MASTER_CSV ALLVOL_MASTER_CSV"
    exit 1
fi
sub_ses_list=$1
thal_master=$2
allvol_master=$3

echo "Assembling results from ${sub_ses_list} ..."

# ---- thalamic master: every per-subject file has the identical header
#      (built from the same thal_prefix), so a plain concat is safe here --
#      no need for python/pandas on this one. ----
rm -f "${thal_master}"
echo "EMPI,EXAM_DATE,${thal_prefix}_L,${thal_prefix}_R,${thal_prefix}_total" > "${thal_master}"

#loop through the same sub_id,ses_id rows the wrapper used, rebuild each
#subject's directory, and pull its one-row thalamic csv. If the subject's
#job never produced one (failed / still running / bad path), write an
#NA-filled row instead of skipping, so this file always has exactly as many
#rows as sub_ses_list.csv, in the same order.
missing=0
while IFS=',' read -r sub_id ses_id; do
    [ -z "${sub_id}" ] && continue
    subj_dir="${data_dir}/sub-${sub_id}/ses-${ses_id}"
    f="${subj_dir}/openmap-t1/thalamic_volume.csv"
    if [ -f "${f}" ]; then
        tail -n +2 "${f}" >> "${thal_master}"
    else
        echo "WARNING: missing ${f} -- writing NA row" >&2
        echo "${sub_id},${ses_id},NA,NA,NA" >> "${thal_master}"
        missing=$((missing + 1))
    fi
done < "${sub_ses_list}"
echo "Thalamic master written -> ${thal_master} (${missing} subject(s) missing output, written as NA)"

# ---- all-volumes master: same NA-row idea as the thalamic master above,
#      plus one extra safety check. Every subject should produce the
#      identical 280-region header (same atlas, same model run), so a plain
#      concat is normally fine -- but if a region ever failed to segment for
#      one subject, its all_volumes.csv would have a different column
#      count/order and a naive cat would silently shift every value over.
#      So: two passes. First, find the first subject with usable output and
#      use its header as the master header (and to count how many NA fields
#      a missing/mismatched row needs). Then loop every row for real,
#      writing real data if it matches the master header, an NA-filled row
#      otherwise -- so this file also always has exactly as many rows as
#      sub_ses_list.csv, in the same order. ----
rm -f "${allvol_master}"

master_header=""
while IFS=',' read -r sub_id ses_id; do
    [ -z "${sub_id}" ] && continue
    f="${data_dir}/sub-${sub_id}/ses-${ses_id}/openmap-t1/all_volumes.csv"
    if [ -f "${f}" ]; then
        master_header=$(head -n1 "${f}")
        break
    fi
done < "${sub_ses_list}"

if [ -z "${master_header}" ]; then
    echo "ERROR: no subject produced an all_volumes.csv -- nothing to assemble" >&2
    exit 1
fi
echo "${master_header}" > "${allvol_master}"

#how many NA fields a stand-in row needs: total columns minus subject,session
n_data_cols=$(( $(echo "${master_header}" | awk -F',' '{print NF}') - 2 ))
na_fields=$(printf ',NA%.0s' $(seq 1 "${n_data_cols}"))

allvol_missing=0
allvol_mismatched=0
while IFS=',' read -r sub_id ses_id; do
    [ -z "${sub_id}" ] && continue
    subj_dir="${data_dir}/sub-${sub_id}/ses-${ses_id}"
    f="${subj_dir}/openmap-t1/all_volumes.csv"

    if [ ! -f "${f}" ]; then
        echo "WARNING: missing ${f} -- writing NA row" >&2
        echo "${sub_id},${ses_id}${na_fields}" >> "${allvol_master}"
        allvol_missing=$((allvol_missing + 1))
        continue
    fi

    this_header=$(head -n1 "${f}")
    if [ "${this_header}" != "${master_header}" ]; then
        echo "WARNING: ${f} has a different header than the master (region set/order" >&2
        echo "         mismatch, likely a failed segmentation) -- writing NA row instead" >&2
        echo "         of misaligned data. Inspect this subject by hand." >&2
        echo "${sub_id},${ses_id}${na_fields}" >> "${allvol_master}"
        allvol_mismatched=$((allvol_mismatched + 1))
        continue
    fi

    tail -n +2 "${f}" >> "${allvol_master}"
done < "${sub_ses_list}"

echo "All-volumes master written -> ${allvol_master} (${allvol_missing} subject(s) missing output, ${allvol_mismatched} written as NA for column mismatch)"
