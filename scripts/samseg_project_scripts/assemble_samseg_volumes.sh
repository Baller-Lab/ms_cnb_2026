#!/bin/bash

### Assembles per-subject SAMSEG CSVs (written by indiv_samseg_script.sh) into
### one project-wide master CSV.
### Pre: every SAMSEG job in the cohort has ended (bsub -w "ended(...)" in the
###      wrapper enforces this -- do not run by hand while jobs are still in
###      flight, or subjects still running will be written as NA).
### Post: MASTER_CSV written with exactly one row per row of SUB_SES_LIST (same
###       order, same count). Missing/failed subjects get an NA-filled row; subjects
###       whose structure list doesn't match the others (e.g. no FLAIR, so SAMSEG ran
###       without the lesion model) keep their ICV but get NA for every structure,
###       instead of misaligned data, so the file always lines up 1:1 with the subject list.
###       Columns: EMPI,EXAM_DATE,samseg_icv,<SAMSEG structures...>
### Uses: MS depression / CNB project -- final step of the SAMSEG pipeline,
###       called by bsub from samseg_wrapper.sh once every per-subject job ends.
### Dependencies: bash, awk
set -euf -o pipefail

# ---- base path: must match indiv_samseg_script.sh, since we rebuild the same
#      subj_dir it wrote each per-subject csv into ----
data_dir="/project/msdepression/data/radiology_pulls_20260610/data"
# --------------------------------------------------------------------------

if [ $# -lt 2 ]; then
    echo "Usage: $0 SUB_SES_LIST MASTER_CSV [SAMSEG_SUBDIR: samseg (T1 run, default) | samseg_flair]"
    exit 1
fi
sub_ses_list=$1
master_csv=$2
#which run to assemble -- the per-subject folder name the wrapper used
samseg_subdir=${3:-samseg}

echo "Assembling SAMSEG results (${samseg_subdir}/) from ${sub_ses_list} ..."

#first pass: use the first subject with usable output as the master header
#(and to know how many NA fields a stand-in row needs)
master_header=""
while IFS=',' read -r sub_id ses_id; do
    [ -z "${sub_id}" ] && continue
    f="${data_dir}/sub-${sub_id}/ses-${ses_id}/${samseg_subdir}/samseg_volumes.csv"
    if [ -f "${f}" ]; then
        master_header=$(head -n1 "${f}")
        break
    fi
done < "${sub_ses_list}"

if [ -z "${master_header}" ]; then
    echo "ERROR: no subject produced a samseg_volumes.csv -- nothing to assemble" >&2
    exit 1
fi
rm -f "${master_csv}"
echo "${master_header}" > "${master_csv}"

#NA fields for a stand-in row = total columns minus EMPI,EXAM_DATE
n_data_cols=$(( $(echo "${master_header}" | awk -F',' '{print NF}') - 2 ))
na_fields=$(printf ',NA%.0s' $(seq 1 "${n_data_cols}"))

#second pass: every row of the subject list, real data if the header matches,
#NA row otherwise
n_missing=0
n_mismatched=0
while IFS=',' read -r sub_id ses_id; do
    [ -z "${sub_id}" ] && continue
    f="${data_dir}/sub-${sub_id}/ses-${ses_id}/${samseg_subdir}/samseg_volumes.csv"

    if [ ! -f "${f}" ]; then
        echo "WARNING: missing ${f} -- writing NA row" >&2
        echo "${sub_id},${ses_id}${na_fields}" >> "${master_csv}"
        n_missing=$((n_missing + 1))
        continue
    fi

    if [ "$(head -n1 "${f}")" != "${master_header}" ]; then
        #keep this subject's ICV (column 3) -- ICV is the main thing we need, and it doesn't
        #depend on the structure list -- but NA every structure column so nothing misaligns
        this_icv=$(sed -n '2p' "${f}" | cut -d, -f3)
        na_struct=$(printf ',NA%.0s' $(seq 1 $((n_data_cols - 1))))
        echo "WARNING: ${f} has a different structure list than the master (e.g. lesion" >&2
        echo "         model on for one subject and off -- no FLAIR -- for another). Keeping its ICV," >&2
        echo "         writing NA for the structures; inspect by hand" >&2
        echo "${sub_id},${ses_id},${this_icv}${na_struct}" >> "${master_csv}"
        n_mismatched=$((n_mismatched + 1))
        continue
    fi

    tail -n +2 "${f}" >> "${master_csv}"
done < "${sub_ses_list}"

n_rows=$(( $(grep -c . "${master_csv}") - 1 ))
echo "SAMSEG master written -> ${master_csv}"
echo "  ${n_rows} rows (should equal the number of rows in ${sub_ses_list})"
echo "  ${n_missing} missing, ${n_mismatched} written as NA for a structure-list mismatch"

#quick sanity summary of ICV so a broken run is obvious right away
#(adult ICV is roughly 1.1-2.0 million mm3)
awk -F',' 'NR > 1 && $3 != "NA" { n++; s += $3; if (min == "" || $3 < min) min = $3; if ($3 > max) max = $3 }
           END { if (n) printf "  ICV: n=%d, mean=%.0f, min=%.0f, max=%.0f mm3\n", n, s/n, min, max }' "${master_csv}"
