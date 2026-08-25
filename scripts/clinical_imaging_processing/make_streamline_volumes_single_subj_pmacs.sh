
### Make streamline volumes ###

### Pre: All streamlines must have been made in dsi studio (these are the nii files)
### Post: 3 csvs that contain 1) subj accession #, date, tract, and volume. roi+roa together, roi alone, roa alone. All , separated
### Uses: Will be getting the volumes of the streamlines for use in later density analyses
### Dependencies: This script requires afni to be installed.

module load afni_openmp #updated

num_cores=1
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${num_cores}

#default fascicle directory
if [ $# == 0 ]
then
     echo "You did not enter a file. Make sure your call makes sense"

else  
    lesion=$1

    #extract important parts of lesion path
    parent_dir=$(echo ${lesion} | perl -pe s'/(.*)\/.*/$1/g')

    #pulls out accession number and date, separated them by a comma
    subj_sess=$(echo ${lesion} | perl -pe s'/.*sub-(.*)\/ses-(.*)\/mni.*/$1,$2/g') #updated this to be \/mni from \/r
    
    echo "Subject directory is $parent_dir"
    
    #files to be stored within the main fiber_tracking_map directory
    output_csv_roa_and_roi="${parent_dir}/fiber_tracking_maps/fiber_volume_values_roa_and_roi.csv"

    #initiate csvs
    rm -f $output_csv_roa_and_roi
    touch $output_csv_roa_and_roi
    echo "subject,session,fascicle,volume" >> $output_csv_roa_and_roi
   
    #go through each fiber, get volume, and store it in csv
	fiber_bundle_type_list="association cerebellum cranial_nerve projection commissural"	
    for fiber_bundle_type in ${fiber_bundle_type_list}; do
    	echo "Fiber bundle type is " $fiber_bundle_type
    	fascicle_volumes=$(ls ${parent_dir}/fiber_tracking_maps/${fiber_bundle_type}/*.nii*) #added fiber_tracking_maps
        for fascicle in ${fascicle_volumes}; do
            fascicle_prefix=$(echo $fascicle | perl -pe 's/.*\/(.*).nii.gz/$1/g')
            volume=$(3dmaskave -quiet -mask SELF -sum ${fascicle})
            echo "${subj_sess},${fascicle_prefix},$volume" >> $output_csv_roa_and_roi
        done
    done

    #make separate files for ROA alone and ROI alone

    output_csv_roa="${parent_dir}/fiber_tracking_maps/fiber_volume_values_roa.csv"
    output_csv_roi="${parent_dir}/fiber_tracking_maps/fiber_volume_values_roi.csv"
    
    #remove old files if they are there
    rm -f $output_csv_roa
    rm -f $output_csv_roi

    #add headers
    echo "subject,session,fascicle,volume_ROA" > $output_csv_roa
    echo "subject,session,fascicle,volume_ROI" > $output_csv_roi

    #Add files specifically
    more $output_csv_roa_and_roi | grep "ROA" >> $output_csv_roa
    more $output_csv_roa_and_roi | grep "ROI" >> $output_csv_roi
fi
