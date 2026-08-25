### ROA Ratio Regressions ###

#####
## Pre: /project/msdepression/data/melissa_martin_files/csv/roi_fiber_volumes_n2336, which contains full paths to the ROI files, can be ammended to do ro
## Post: Analysis
## Uses: 1) reads in the ROIs, puts them in a data frame (columns are accession num/date/each fascicle), one row per subjected per date
#        2) Performers univariate analyses, depression diagnosis versus not
## Dependencies: R 3.6.3

#include packages
library(dbplyr)

#set directories
homedir<-'/project/msdepression/'

#analysis type
region_type="roi"

#set params
suffix <- "fiber_volume_values"
num_subjs = 104
date = 20260619

#read in template fascicle volumes
template_full_volumes <- read.csv(paste0(homedir, '/templates/dti/HCP_YA1065_tractography/fiber_volume_values.csv'), header = T)
fascicle_names <- template_full_volumes$fascicle

### Read in file with all full paths to region volumes
region_volume_csv <- read.table(paste0(homedir, '/data/radiology_pulls_20260610/data/', region_type, '_', suffix, '_n', num_subjs, '_', date), header = F, stringsAsFactors = F)
region_volume_csv$V1 <- as.character(region_volume_csv$V1)

#outfile, named for number of subjects
outfile <- paste0(homedir, "/results/fascicle_volumes_all_subjects_", region_type, "_n", dim(region_volume_csv)[1], '_', date, ".csv")

#make data frame, 1 row per subject, num rows = num rows in region_volume_csv
volumes_df <- data.frame(matrix(nrow = dim(region_volume_csv)[1], ncol = 89))
names(volumes_df) <- c("EMPI", "EXAM_DATE", as.character(fascicle_names))
#loop through region_volume_csv, read in df corresponding to each row of region_volume_csv, extract accession num and date,
## and transpose fiber volumes from column to rows. append accession num/date/region_volumes row into big matrix

for (subj in 1:dim(region_volume_csv)[1]) {
  file_path <- region_volume_csv$V1[subj]
  region_volume_data <- read.csv(file_path, header = T, sep = ",")
  accession_num<- region_volume_data[1,1]
  date <- region_volume_data[1,2]
  volumes <- t(region_volume_data[,4])
  volumes[is.na(volumes)] <- 0
  volumes <- volumes/template_full_volumes$volume
  row_to_add <- cbind(accession_num, date, volumes)
  volumes_df[subj,]<- row_to_add
}

write.csv(file=outfile, volumes_df, quote = FALSE, row.names = FALSE)






