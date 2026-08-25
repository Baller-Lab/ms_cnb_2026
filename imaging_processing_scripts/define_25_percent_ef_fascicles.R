#############################
## Define 25% ef fascicles ##
#############################
#Pre: /project/msdepression/results/streamline_volume_within_ef_network_FDR0_01.csv
#Post: /project/msdepression/results/streamline_volume_within_ef_network_FDR0_01_25_percentile.csv
#Uses: Reads in the /project/msdepression/results/streamline_volume_within_ef_network_FDR0_01.csv, sorts the fascicles by volume of overlap, assign 0 if no overlap, 1 if minimal overlap, 2 if top 25%
#dependencies: Any R will do
# Read data

df <- read.csv(
  "/project/msdepression/results/streamline_volume_within_ef_network_FDR0_01.csv",
  header = TRUE,
  sep = ","
)

#replace NA with 0
df$non_zero_voxels_in_ef_map[is.na(df$non_zero_voxels_in_ef_map)] <- 0

# Initialize
df$inEFMask <- 1

# No overlap = 0
df$inEFMask[df$non_zero_voxels_in_ef_map == 0] <- 0

# 75th percentile across ALL fascicles
top25_cutoff <- quantile(
  df$non_zero_voxels_in_ef_map,
  probs = 0.75,
  na.rm = TRUE
)

# Top 25% = 2
df$inEFMask[
  df$non_zero_voxels_in_ef_map >= top25_cutoff &
  df$non_zero_voxels_in_ef_map > 0
] <- 2

# Save
write.csv(
  df,
  "/project/msdepression/results/streamline_volume_within_ef_network_FDR0_01_25_percentile.csv",
  row.names = TRUE
)

table(df$inEFMask)