#!/bin/bash
# Pre:  - Bias-corrected skull-stripped T1 exists at
#         $data_dir/sub-{empi}/ses-{date}/bias_correction/T1_brain_n4.nii.gz
# Post: - fast/ directory created at $data_dir/sub-{empi}/ses-{date}/fast/
#       - FSL FAST segmentation files written to fast/
#       - total_fast_brain_volume_values.csv written to fast/ with columns:
#         EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume
# Uses: Runs FSL FAST on the bias-corrected skull-stripped T1, extracts CSF,
#       GM, and WM volumes using fslstats, and writes per-subject CSV
# Dependencies: FSL, apptainer

set -euf -o pipefail

export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$LSB_DJOB_NUMPROC

sub=$1
ses=$2
data_dir=$3

t1_input="${data_dir}/sub-${sub}/ses-${ses}/bias_correction/T1_brain_n4.nii.gz"
fast_dir="${data_dir}/sub-${sub}/ses-${ses}/fast"
output_prefix="${fast_dir}/fast"
output_csv="${fast_dir}/total_fast_brain_volume_values.csv"

mkdir -p ${fast_dir}

echo "Running FAST for sub-${sub} ses-${ses}..."

# Run FAST
fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -o ${output_prefix} ${t1_input}

# Extract volumes
csf_vol=$(fslstats ${output_prefix}_pve_0.nii.gz -V | cut -f 2 -d ' ')
gm_vol=$(fslstats ${output_prefix}_pve_1.nii.gz -V | cut -f 2 -d ' ')
wm_vol=$(fslstats ${output_prefix}_pve_2.nii.gz -V | cut -f 2 -d ' ')
total_volume=$(echo "${gm_vol} + ${wm_vol}" | bc)

echo "CSF: $csf_vol  GM: $gm_vol  WM: $wm_vol  Total: $total_volume"

# Write per-subject CSV
rm -f $output_csv
echo "EMPI,EXAM_DATE,csf_volume,gm_volume,wm_volume,total_volume" > $output_csv
echo "${sub},${ses},${csf_vol},${gm_vol},${wm_vol},${total_volume}" >> $output_csv

echo "Completed FAST for sub-${sub} ses-${ses}."