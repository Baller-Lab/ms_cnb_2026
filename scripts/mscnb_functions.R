### Pre: none -- this script only defines functions, it does not run analysis on its own
### Post: all functions below are loaded into the calling session's environment
### Uses: source()'d from cnb_lesion_structural_prl_final_analyses_post_replication_20260917.Rmd.
###       Pared-down, MS-CNB-paper-only copy of msdep_prospective_functions.R -- keeps just the
###       functions that script calls (plus the helpers those call internally):
###         norming:      get_norms_kosha_data, zscores_kosha_norms
###         imaging LMs:  run_item_imaging_lm
###         table cells:  fmt_tp, make_col, get_n, fmt_tp_nostar, make_col_nostar
###         t-tests:      run_one_sample_t
###         supp ANOVAs:  make_supp_domain_long, run_supp_domain_anova, make_supp_domain_plot
###       Everything else (depression/PRL table printers, demographics, task plots, sex
###       comparisons, mixed-model specificity test) stays in msdep_prospective_functions.R.
###       The two copies are now independent -- a fix to a shared function needs to go in both.
### Dependencies: dplyr, tidyr, tibble, purrr, broom, ggplot2, patchwork, knitr, kableExtra,
###               rstatix, emmeans, ggsignif (last three for the supp ANOVA helpers, called via pkg::)
###
### NOTE ON SCOPING: run_item_imaging_lm takes icv_covariate_predictors as an argument
### with a same-named default (icv_covariate_predictors = icv_covariate_predictors).
### That default is still resolved via lexical scoping against the calling script's
### global environment if you don't pass it explicitly -- so a script that sources this
### file and calls it still needs an icv_covariate_predictors object in scope unless it
### passes its own value in. Intentional: it's a documented, overridable parameter
### instead of a silent global lookup, since the set of predictors needing an ICV
### covariate could change per-analysis in the future.

# patchwork/knitr/kableExtra aren't used by the functions themselves, but the analysis
# script relies on this file loading them (wrap_plots, kable, ...)
library(dplyr)
library(tidyr)
library(tibble)
library(purrr)
library(broom)
library(ggplot2)
library(patchwork)
library(knitr)
library(kableExtra)

# ============================================================
# NORMING
# ============================================================

get_norms_kosha_data <- function(age, sex, cnb_task, acc_or_rt, norm_df){

  # Sample age value
#age <- 23

  #clip off any text in front of period
cnb_task_prefix_removed <- toupper(gsub("^[^.]*\\.", "", cnb_task))
#print(cnb_task_prefix_removed)

df_filtered_age_and_sex <- norm_df %>%
  filter(Variable == cnb_task_prefix_removed) %>%
  filter(Sex == as.character(sex)) %>%
  filter(grepl("across_genus", Title))

  mean_norms <- df_filtered_age_and_sex$Mean[(df_filtered_age_and_sex$Min.age <= age) & ( df_filtered_age_and_sex$Max.age >= age)]

  sd_norms <- df_filtered_age_and_sex$Standard.deviation[(df_filtered_age_and_sex$Min.age <= age) & ( df_filtered_age_and_sex$Max.age >= age)]

  return(list(mean_norms, sd_norms))
}

########### CREATE A FUNCTION TO CREATE ZSCORES FOR MGI+MS ###########
# This function will be used to create the z-scores for our MS participants
zscores_kosha_norms <- function(data_frame, norm_column_name, acc_or_rt, cnb_column_name, norm_df)
#zscores <- function(data_frame, column_name, norm_df)
{
  num_elements <- eval(parse(text = paste0("length(data_frame$", cnb_column_name, ")")))
  zscore_array <- array(dim = num_elements, data = NA)
  for (person in 1:num_elements){
      item <- eval(parse(text = paste0("data_frame$", cnb_column_name, "[", person, "]")))
#print(item)
      age <- eval(parse(text = paste0("data_frame$test_sessions_v.age[", person, "]")))
 #     print(age)
      sex <-eval(parse(text = paste0("data_frame$test_sessions_v.gender[", person, "]")))
  #    print(sex)
      if (is.na(age) || is.na(sex) || is.na(item)) next
      norms <- get_norms_kosha_data(age, sex, norm_column_name, acc_or_rt, norm_df)
      norms_mean = norms[[1]]
    #  print(norms_mean)
      norms_sd = norms[[2]]
      #print(norms_sd)
      zscore <- (item-norms_mean)/norms_sd
   #   print(zscore)
      zscore_array[person] <- zscore

  }
  return(zscore_array)
}

# ============================================================
# ITEM-LEVEL IMAGING LMs
# ============================================================

run_item_imaging_lm<- function(items, img_predictors, data, exclude_zero = FALSE,
                                icv_covariate_predictors = icv_covariate_predictors) {
  map(img_predictors, function(img_var) { #looks like map runs through everything and then sends to transmute that does the correction, so should be correction over all the items/scales within one imaging variable
    covariates <- c("test_sessions_v.age", "test_sessions_v.gender")
    if (img_var %in% icv_covariate_predictors) covariates <- c(covariates, "intracranial_volume")

    tibble(outcome = items) %>%
      mutate(
        imaging_measure = img_var,
        model  = map(outcome, ~ {
                                   d <- data %>%
                                     select(all_of(c(.x, img_var, covariates))) %>% #from df, select item, imaging var, age(, ICV)
                                     na.omit()
                                   if (exclude_zero) d <- d %>% filter(.data[[img_var]] != 0) #remove if there is no value in image var/no signal, no coverage
                                   v <- var(d[[.x]], na.rm = TRUE)
                                   if (nrow(d) < 5 || is.na(v) || v == 0 || length(unique(d$test_sessions_v.gender)) < 2) return(NULL) #also skip if sex is degenerate (all one sex) after filtering -- lm() can't fit a contrast on a single-level factor #if there are not enough rows/vars , clinical item has no variance
                                   lm(reformulate(c(img_var, covariates), response = .x), data = d) #linear model item ~ imaging variable + age(+ ICV)
                                 }),
        img_lm = map(model, ~ if (is.null(.x)) tibble() else tidy(.x, conf.int = TRUE) %>% filter(term == img_var)), #if this is successful, grab a confidence interval for the variable
        glance = map(model, ~ if (is.null(.x)) tibble() else glance(.x)) #if model is null, tibble, if not, grab stats
      ) %>%
      transmute(
        imaging_measure, #this is img_var
        outcome, #this is the bdi/etc
        estimate  = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$estimate), #grabbing stats
        std.error = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$std.error),
        statistic = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$statistic),
        conf.low  = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$conf.low),
        conf.high = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$conf.high),
        p_value   = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$p.value),
        n         = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$nobs),
        r2        = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$r.squared),
        adj_r2    = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$adj.r.squared),
        df_residual  = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$df.residual), # changing name to df_residual for consistency with make_col - EAH 9/17/2026
        partial_r = statistic / sqrt(statistic^2 + df_residual), # changing name to df_residual for consistency with make_col - EAH 9/17/2026
        d         = 2 * partial_r / sqrt(1 - partial_r^2),
        p_fdr     = p.adjust(p_value, method = "fdr"),
        p_bonf    = p.adjust(p_value, method = "bonferroni"),
        F_value   = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$statistic), #whole-model F-test (glance() already computes this, no need for summary(.x)$fstatistic)
        F_df1     = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$df),
        F_df2     = df_residual, # changing name to df_residual for consistency with make_col - EAH 9/17/2026
        F_p_value = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$p.value),
        F_fdr     = p.adjust(F_p_value, method = "fdr")
      )
  }) %>%
    bind_rows() #correction (p_fdr/p_bonf/F_fdr) is scoped per imaging predictor, across that predictor's items -- not across all imaging predictors combined
}

# ============================================================
# SUMMARY / TABLE HELPERS
# ============================================================

# format helper: "t(p), d=X.XX*" with * if FDR < 0.05
fmt_tp <- function(t, p, fdr, df) { # passing df here directly rather than computing it via n - EAH 9/17/2026
  stars <- ifelse(!is.na(fdr) & fdr < 0.05, "*", "")
  partial_r <- t / sqrt(t^2 + df)
  d <- 2 * partial_r / sqrt(1 - partial_r^2)
  ifelse(is.na(t), "—",
         paste0(sprintf("%.2f", t), " (", sprintf("%.3f", p), "), d=",
                sprintf("%.2f", d), stars))
}

# pull lesion_count and volume from cog_imaging_results
make_col <- function(results, predictor) {
  results %>%
    filter(imaging_measure == predictor) %>%
    select(outcome, statistic, p_value, p_fdr, n, df_residual) %>% # add df_residual - EAH 9/17/2026
    mutate(cell = fmt_tp(statistic, p_value, p_fdr, df_residual)) %>% # pass df_residual, remove n - EAH 9/17/2026
    select(outcome, cell)
}

# helper to get median n for a predictor (n can vary slightly by outcome due to missingness)
get_n <- function(results, predictor) {
  results %>%
    filter(imaging_measure == predictor) %>%
    pull(n) %>%
    median(na.rm = TRUE) %>%
    round()
}

fmt_tp_nostar <- function(t, p, df) { # passing df here directly rather than computing it via n - EAH 9/17/2026
  partial_r <- t / sqrt(t^2 + df)
  d <- 2 * partial_r / sqrt(1 - partial_r^2)
  ifelse(is.na(t), "—",
         paste0(sprintf("%.2f", t), " (", sprintf("%.3f", p), "), d=", sprintf("%.2f", d)))
}

make_col_nostar <- function(results, predictor) {
  results %>%
    filter(imaging_measure == predictor) %>%
    select(outcome, statistic, p_value, n, df_residual) %>% # add df_residual - EAH 9/17/2026
    mutate(cell = fmt_tp_nostar(statistic, p_value, df_residual)) %>% # pass df_residual, remove n - EAH 9/17/2026
    select(outcome, cell)
}

# ============================================================
# ONE-SAMPLE / TASK T-TESTS + PLOTS
# ============================================================

run_one_sample_t <- function(x, label) {
  x_clean <- x[!is.na(x)]
  tt <- t.test(x_clean, mu = 0)
  d  <- mean(x_clean) / sd(x_clean)
  tibble(
    measure   = label,
    n         = length(x_clean),
    mean_z    = round(mean(x_clean), 3),
    sd_z      = round(sd(x_clean), 3),
    t         = round(tt$statistic, 2),
    df        = round(tt$parameter, 0),
    p         = round(tt$p.value, 4),
    cohens_d  = round(d, 2)
  )
}

# ============================================================
# REPEATED-MEASURES ANOVA ACROSS COGNITIVE DOMAINS (SUPPLEMENTARY)
# ============================================================
# Domains are within-subject (every participant contributes a score to every domain),
# so these run a one-way *repeated-measures* ANOVA (subject as the error stratum),
# not a between-groups ANOVA. Needs rstatix, emmeans, ggsignif -- called with pkg::
# rather than library() so nothing gets masked.

# Long format, one row per subject x domain. outcome_cols is a named vector,
# domain label -> per-subject domain z-score column, in plotting order, e.g.
# c(`Executive Function` = "ef_acc", Memory = "mem_acc"). subject_id is the row
# number rather than bblid so n matches the other analyses (one row = one
# participant). Complete cases only -- RM ANOVA needs every domain per subject.
make_supp_domain_long <- function(outcome_cols, cog_domains_data) {
  cog_domains_data %>%
    mutate(subject_id = row_number()) %>%
    select(subject_id, all_of(outcome_cols)) %>%    # named all_of() renames cols to domain labels
    filter(if_all(-subject_id, is.finite)) %>%
    pivot_longer(-subject_id, names_to = "Domain", values_to = "z") %>%
    mutate(Domain     = factor(Domain, levels = names(outcome_cols)),
           subject_id = factor(subject_id))
}

# Omnibus RM ANOVA + (if significant) Tukey-adjusted pairwise contrasts
run_supp_domain_anova <- function(domain_long) {
  rm_anova <- rstatix::anova_test(data = domain_long, dv = z, wid = subject_id, within = Domain)
  anova_tbl <- rstatix::get_anova_table(rm_anova, correction = "auto") %>% as_tibble()

  posthoc <- NULL
  if (anova_tbl$p < 0.05) {
    # sum-to-zero contrasts up front, otherwise emmeans tries to refit the aov itself
    # and can't find domain_long from inside this function
    rm_aov <- aov(z ~ Domain + Error(subject_id / Domain), data = domain_long,
                  contrasts = list(Domain = "contr.sum"))
    posthoc <- emmeans::emmeans(rm_aov, ~ Domain) %>%
      pairs(adjust = "tukey") %>%
      as_tibble() %>%
      mutate(sig = case_when(p.value < 0.001 ~ "***",
                             p.value < 0.01  ~ "**",
                             p.value < 0.05  ~ "*",
                             TRUE            ~ ""))
  }

  list(n = n_distinct(domain_long$subject_id),
       mauchly = rm_anova$`Mauchly's Test for Sphericity`,
       anova = anova_tbl,
       posthoc = posthoc)
}

# Bar plot of the 4 domains for one metric -- same bar/95% CI/theme conventions as
# the main domain figure above. Brackets mark Tukey-significant pairs (only drawn
# when the omnibus ANOVA was significant, so posthoc exists).
make_supp_domain_plot <- function(domain_long, anova_result, fill_color) {
  plot_data <- domain_long %>%
    group_by(Domain) %>%
    summarise(n = n(), mean_z = mean(z), se = sd(z) / sqrt(n),
              ci95_half_width = qt(0.975, n - 1) * se, .groups = "drop")

  p <- ggplot(plot_data, aes(x = Domain, y = mean_z)) +
    geom_bar(stat = "identity", width = 0.7, fill = fill_color) +
    geom_errorbar(aes(ymin = mean_z - ci95_half_width, ymax = mean_z + ci95_half_width),
                  width = 0.2, linewidth = 0.7) +
    geom_hline(yintercept = 0, linewidth = 0.5) +
    labs(y = "Mean z-score (+/- 95% C.I.)", x = NULL) +
    theme_classic() +
    theme(
      axis.text.x = element_text(size = 14, color = "black"),
      axis.text.y = element_text(size = 11, color = "black"),
      axis.title.y = element_text(size = 14, margin = margin(r = 10)),
      axis.line = element_line(linewidth = 1),
      panel.grid = element_blank()
    )

  sig_pairs <- if (is.null(anova_result$posthoc)) tibble() else
    anova_result$posthoc %>% filter(sig != "")

  if (nrow(sig_pairs) > 0) {
    # emmeans contrast labels look like "Executive Function - Memory"
    comparisons <- strsplit(sig_pairs$contrast, " - ", fixed = TRUE)
    # stack brackets above the tallest CI, one step apart so they don't overlap
    y_top  <- max(plot_data$mean_z + plot_data$ci95_half_width, 0)
    y_step <- 0.12 * diff(range(c(plot_data$mean_z - plot_data$ci95_half_width, y_top)))
    p <- p + ggsignif::geom_signif(
      comparisons = comparisons,
      annotations = sig_pairs$sig,
      y_position  = y_top + y_step * seq_along(comparisons),
      tip_length  = 0.01, textsize = 6, vjust = 0.5
    )
  }
  p
}

