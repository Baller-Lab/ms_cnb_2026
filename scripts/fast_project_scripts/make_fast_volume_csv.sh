#!/bin/bash
# Pre:  - every FAST task has ended (the dependent bsub -w "ended(...)" from
#         get_fast_total_brain_volume_all_subjs.sh enforces this)
#       - total_fast_brain_volume_values.csv exists per subject in ${fast_subdir}/
# Post: - MASTER_CSV created with one row per row of SUB_SES_LIST (same order, same
#         count); subjects with no output get an NA row instead of being dropped
#         columns: EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume,fast_icv
# Uses: Loops through the subject list, finds each subject's per-subject CSV, and
#       appends its data row to the consolidated output file. Prints a summary of
#       the CSF+GM+WM range at the end so a broken run (like the 6/24 one, where some
#       values were 0.25 million mm3) is obvious right away.
# Dependencies: bash, awk

set -euf -o pipefail

if [ $# -lt 4 ]; then
    echo "Usage: $0 SUB_SES_LIST DATA_DIR FAST_SUBDIR MASTER_CSV"
    exit 1
fi
sub_ses_list=$1
data_dir=$2
fast_subdir=$3
output_csv=$4

header="EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume,fast_icv"
rm -f "${output_csv}"
echo "${header}" > "${output_csv}"

n_missing=0
while IFS=',' read -r sub ses; do
    [ -z "${sub}" ] && continue
    indiv_csv="${data_dir}/sub-${sub}/ses-${ses}/${fast_subdir}/total_fast_brain_volume_values.csv"

    if [ ! -f "${indiv_csv}" ]; then
        echo "  No volume CSV found for sub-${sub} ses-${ses} -- writing NA row" >&2
        echo "${sub},${ses},NA,NA,NA,NA,NA" >> "${output_csv}"
        n_missing=$((n_missing + 1))
        continue
    fi

    tail -n 1 "${indiv_csv}" >> "${output_csv}"
done < "${sub_ses_list}"

n_rows=$(( $(grep -c . "${output_csv}") - 1 ))
echo "Done. Output written to ${output_csv}"
echo "  ${n_rows} rows (should equal the number of rows in ${sub_ses_list}), ${n_missing} missing"

#sanity summary -- every subject should be in a similar range now
awk -F',' 'NR > 1 && $7 != "NA" { n++; s += $7; if (min == "" || $7 < min) min = $7; if ($7 > max) max = $7 }
           END { if (n) printf "  CSF+GM+WM (inside brain mask): n=%d, mean=%.0f, min=%.0f, max=%.0f mm3\n", n, s/n, min, max }' "${output_csv}"
