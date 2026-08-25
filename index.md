<br>
<br>



### Project Lead
Erica B. Baller

### Brief Project Description:
125 participants with MS were included (75.8%F, mean age 43.1). Cognitive assessments with CNB were performed and summarized by overall accuracy and speed, and by cognitive domain. Patterns of cognitive disease were then evaluated in relation to lesion burden (count and volume, n=102), GM, WM, and thalamic volume (n=103) from research-grade clinical scans, and PRL burden (count and volume, n=27) from 7T. 

### Authors/Collaborators:
Erica B. Baller, M.D., M.S., Elizabeth A. Horwath, Ph.D., Millie R. Sach, B.A., Elena C. Cooper, B.A., Nikka Bakhtiar, M.S., Amit Bar-Or, M.D., Rachel B. Brandstadter, M.D., Ruben C. Gur, Ph.D., Dina A. Jacobs, M.D., Christopher M. Perrone, M.D., David R. Roalf, Ph.D., Kosha Ruparel, M.S.E., J. Cobb Scott, Ph.D., Theodore D. Satterthwaite, M.D., M.A., Russell T. Shinohara, Ph.D., Matthew K. Schindler, M.D., Ph.D. <img width="468" height="84" alt="image" src="https://github.com/user-attachments/assets/da632e3e-0d1e-42a2-99ec-33dd6324d288" />


### Project Start Date:
4/2026

### Current Project Status:
Completed

### Dataset:
K23 Multiple Sclerosis Cohort (collected between July 1, 2023 and April 30, 2026)

### Github repo:
[https://github.com/Baller-Lab/ms_cnb_2026/](https://github.com/Baller-Lab/ms_cnb_2026)

### Website
[https://Baller-Lab.github.io/msanxiety/](https://Baller-Lab.github.io/ms_cnb_2026/)

### Slack Channel:
#ms-lesion_count_and_mimosa

### Zotero library:
K23 MS and Depression

### Current work products:
ECTRIMS 2026 Poster - "Domain-Specific Cognitive Impairments Identified by the Penn Computerized Neurocognitive Battery Are Associated with Paramagnetic Rim Lesion Burden"


### Path to Data on Filesystem **PMACS**

MS Proviers (local computer)

     /Users/eballer/BBL/general_emr_relevant_spreadsheets//msproviders.csv
     
Medication information: 
     
[ms_medications_brand_and_generic](https://github.com/Baller-Lab/msanxiety/tree/main/medication_data/ms_medications_brand_and_generic_cleaned.csv) 

[nami_psych_meds](https://github.com/Baller-Lab/msanxiety/tree/main/medication_data/nami_psych_meds_antidepressants_plus_gabapentin_and_amitriptyline_benzos_beta_blockers.csv)


Subject imaging data (cluster): 

     /project/msanxiety/data/subj_directories

Cubids (cluster): 

     /project/msanxiety/cubids/v1_validation.csv
     /project/msanxiety/CuBIDS_outputs/*
     
MIMoSA QA info (cluster):

     /project/msanxiety/data/melissa_martin_files/csv/mimosa_dataframe

Volume of all lesions (NOT fascicles) for each subject (cluster): 

     /project/msanxiety/results/mimosa_binary_masks_hcp_space_20211026_n2336_volumes.csv

<br>
<br>

# CODE DOCUMENTATION

**The analytic workflow implemented in this project is described in detail in the following sections. Analysis steps are described in the order they were implemented; the script(s) used for each step are identified and links to the code on github are provided.** 
<br>

### * Functions for project *
[ms_functions.R](https://github.com/Baller-Lab/msanxiety/tree/main/scripts/jama_scripts/ms_functions.R)

### Sample Construction

We first constructed our sample from n=890 individuals who were diagnosed with multiple sclerosis by a Multiple Sclerosis provider and received their clinical scans at the University of Pennsylvania. 

The following code takes the n=825 sample, and goes through a variety of exclusions to get the final n. Specifically, after excluding 11 participants with poor mimosa quality (23) or streamline filtering (55), 814 participants were eligible for anxiety classification.  Participants with MS were identified from the electronic medical record and stratified into three age- and sex-matched groups: 1) MS without anxiety (MS+noA); 2) MS with mild anxiety (MS+mildA), 3) MS with severe anxiety (MS+severeA). MS+noA included persons who had no psychiatric diagnosis, took no psychiatric medications, and were asymptomatic on PHQ 2/9 (n = 99, age (SD) = 49.4 (11.7), % female = 75). MS+mildA included persons with either a diagnosis of an anxiety disorder (F40*) or a prescription for an anti-anxiety medication (n = 249, age (SD) = 47.1 (11.1), % female = 82). MS+severeA included persons who had both an anxiety disorder and were taking an anti-anxiety medication (n = 24, age (SD) = 47.0 (12.2), % female = 79).

[clean_dac_pull_icd10_codes_and_make_clean_df_post_replication.R](https://github.com/Baller-Lab/msanxiety/tree/main/scripts/FINAL_scripts_clean/clean_dac_pull_icd10_codes_and_make_clean_df_post_replication.R)

### Automated white matter lesion segmentation

After we obtained our sample, we used the Method for Intermodal Segmentation Analysis (MIMoSA) to extract white matter lesions for each subject. MIMoSA has been previously described: 

Valcarcel AM, Linn KA, Vandekar SN, Satterthwaite TD, Muschelli J, Calabresi PA, Pham DL, Martin ML, Shinohara RT. MIMoSA: An Automated Method for Intermodal Segmentation Analysis of Multiple Sclerosis Brain Lesions. J Neuroimaging. 2018 Jul;28(4):389-398. [doi: 10.1111/jon.12506](https://pubmed.ncbi.nlm.nih.gov/29516669/). Epub 2018 Mar 8. PMID: 29516669; PMCID: PMC6030441.

### Brain segmentation

To obtain a measure of total brain volume (minus CSF), I used FSL's fast on all T1w images (post n4 and ws). I then summed the grey matter and white matter volume to create a measure of total brain volume (total_volume).

Wrapper script:
[get_fast_total_brain_volume_all_subjs.sh](https://github.com/Baller-Lab/msanxiety/tree/main/scripts/jama_scripts/get_fast_total_brain_volume_all_subjs.sh)

Segmentation script:
[make_fast_files_single_subj_pmacs.sh](https://github.com/Baller-Lab/msanxiety/tree/main/scripts/jama_scripts/make_fast_files_single_subj_pmacs.sh)

Volume calculation script:
[make_fast_volume_csv.sh](https://github.com/Baller-Lab/msanxiety/tree/main/scripts/jama_scripts/make_fast_volume_csv.sh)

### Thalamus Segmentation

### PRL preprocessing

### Final group level analysis

This script is run locally, on R. It does all second level/group data analysis. Main steps summarized below.

[MS_cnb_manuscript_FINAL.Rmd](https://github.com/Baller-Lab/msanxiety/tree/main/scripts/jama_scripts/MSAnxiety_manuscript_JAMA_revision_20250304_95_CI_FINAL.Rmd)

#### Overall Cognitive Results

#### Cognitive Results by Domain

#### Cognitive Results by Domain vs Lesion, GM, WM, Thalamus, and PRL Metrics


#### Disease burden summary measures
I wanted to look specifically at mean disease burden in uncinate fasiculus, given previous literature suggesting that the uncinate is the main white matter bundle connecting mPFC and amygdala, core brain areas associated with anxiety disorders. 
    
#### Main effect of Diagnosis

A gam with mean_UF_vol as dependent variable, modeling main effect of anxiety diagnosis (MS+noA vs MS+severeA), with sex, total brain volume, and spline of age as covariates.
     
     gam(mean_UF_vol ~ Diagnosis + osex+s(PAT_AGE_AT_EXAM, k = 4, fx = F)+ total_volume, data = uncinate_by_dx_df)

#### Parametric effect of anxiety "dose"

A gam with mean_UF_vol as dependent variable, modeling main effect of anxiety dose (dose = 0 (MS+nA), 1 (MS+mildA), or 2 (MS+severeA)), with sex and spline of age as covariates.
     
     gam(mean_UF_vol ~ anxiety_dose + osex + s(PAT_AGE_AT_EXAM, k = 4, fx = F)+ total_volume, data=df_demo_and_fascicles_no_unclass_anxiety_dose)

#### Sensitivity analyses
As a comparison, I also looked specifically at fornix, which is another subcortical fiber connecting prefrontal and medial temporal lobe (anterior cingulate/hippocampus), primarily involved in cognition/memory, rather than anxiety (N.S.) 

     gam(mean_fornix_volume ~ anxiety_dose + osex + s(PAT_AGE_AT_EXAM, k = 4, fx = F)+ total_volume, data=df_demo_and_fascicles_no_unclass_anxiety_dose)

To test whether this was specific to anxiety diagnosis and did not simply reflect general internalizing symptoms, I also evaluated mean uncinate volume in patients with MS+Depression (199) or MS+noDep (99) in this cohort (N.S.) 
     
     gam(mean_UF_vol ~ depDiagnosis + osex + s(PAT_AGE_AT_EXAM, k=4, fx=F)+ total_volume, data = df_dep)

I also evaluated whether lesion volume was associated with anxiety diagnosis, severity, and depression, and all were significant, suggesting that total lesion volume is associated with general psychopathology.

     gam(volume_of_mimosa_lesions ~ (depDiagnosis|Diagnosis|anxiety_dose) + osex + s(PAT_AGE_AT_EXAM, k=4, fx=F)+ total_volume, data=(df_dep|uncinate_by_dx_df|df_demo_and_fascicles_no_unclass_anxiety_dose)) 

