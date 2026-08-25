### Pre: none -- this script only defines functions, it does not run analysis on its own
### Post: all functions below are loaded into the calling session's environment
### Uses: source()'d from ~/Library/CloudStorage/Box-Box/BBL/msdepression/2026_k23_radiology_pull_n104/scripts/cnb_lesion_structural_prl_final_analyses_pre_replication_20260818.Rmd;
###       intended to be source()'d from any other script in this project that needs
###       the same norming, LM, summary-table, or plotting helpers, instead of
###       re-copying them
### Dependencies: dplyr, tidyr, tibble, purrr, broom, ggplot2, patchwork, knitr, kableExtra, lme4, lmerTest
###
### NOTE ON SCOPING: run_item_imaging_lm and run_item_imaging_lm_by_group take
### icv_covariate_predictors as an argument with a same-named default
### (icv_covariate_predictors = icv_covariate_predictors). That default is still
### resolved via lexical scoping against the calling script's global environment
### if you don't pass it explicitly -- so a script that sources this file and calls
### either function still needs an icv_covariate_predictors object in scope unless
### it passes its own value in. This is intentional: the value is the same at every
### call site today, but it's now a documented, overridable parameter instead of a
### silent global lookup, since the set of predictors needing an ICV covariate could
### change per-analysis in the future.

library(dplyr)
library(tidyr)
library(tibble)
library(purrr)
library(broom)
library(ggplot2)
library(patchwork)
library(knitr)
library(kableExtra)
library(lme4)
library(lmerTest)

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
        df_resid  = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$df.residual),
        partial_r = statistic / sqrt(statistic^2 + df_resid),
        d         = 2 * partial_r / sqrt(1 - partial_r^2),
        p_fdr     = p.adjust(p_value, method = "fdr"),
        p_bonf    = p.adjust(p_value, method = "bonferroni"),
        F_value   = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$statistic), #whole-model F-test (glance() already computes this, no need for summary(.x)$fstatistic)
        F_df1     = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$df),
        F_df2     = df_resid,
        F_p_value = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$p.value),
        F_fdr     = p.adjust(F_p_value, method = "fdr")
      )
  }) %>%
    bind_rows() #correction (p_fdr/p_bonf/F_fdr) is scoped per imaging predictor, across that predictor's items -- not across all imaging predictors combined
}

#fdr's by family, not across EVERYTHING
run_item_imaging_lm_by_group <- function(items, item_scales, img_predictors, data, exclude_zero = FALSE,
                                          icv_covariate_predictors = icv_covariate_predictors) {
  # items and item_scales must be the same length and in the same order,
  # e.g. items = c("phq_adult_1", ..., "bdi_ii_1", ..., "promis_dep_short_adult_1", ...)
  #      item_scales = c("PHQ-9", ..., "BDI-II", ..., "PROMIS-D", ...)
  # ICV covariate: see icv_covariate_predictors above -- same per-predictor rule.

  scale_lookup <- tibble(outcome = items, scale = item_scales)

  map(img_predictors, function(img_var) {
    covariates <- c("test_sessions_v.age", "test_sessions_v.gender")
    if (img_var %in% icv_covariate_predictors) covariates <- c(covariates, "intracranial_volume")

    tibble(outcome = items) %>%
      left_join(scale_lookup, by = "outcome") %>%
      mutate(
        imaging_measure = img_var,
        model  = map(outcome, ~ {
                                   d <- data %>%
                                     select(all_of(c(.x, img_var, covariates))) %>%
                                     na.omit()
                                   if (exclude_zero) d <- d %>% filter(.data[[img_var]] != 0)
                                   v <- var(d[[.x]], na.rm = TRUE)
                                   if (nrow(d) < 5 || is.na(v) || v == 0 || length(unique(d$test_sessions_v.gender)) < 2) return(NULL) #also skip if sex is degenerate (all one sex) after filtering -- lm() can't fit a contrast on a single-level factor
                                   lm(reformulate(c(img_var, covariates), response = .x), data = d)
                                 }),
        img_lm = map(model, ~ if (is.null(.x)) tibble() else tidy(.x, conf.int = TRUE) %>% filter(term == img_var)),
        glance = map(model, ~ if (is.null(.x)) tibble() else glance(.x))
      ) %>%
      transmute(
        imaging_measure,
        outcome,
        scale,
        estimate  = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$estimate),
        std.error = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$std.error),
        statistic = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$statistic),
        conf.low  = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$conf.low),
        conf.high = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$conf.high),
        p_value   = map_dbl(img_lm, ~ if (nrow(.x) == 0) NA_real_ else .x$p.value),
        n         = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$nobs),
        r2        = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$r.squared),
        adj_r2    = map_dbl(glance, ~ if (nrow(.x) == 0) NA_real_ else .x$adj.r.squared)
      ) %>%
      group_by(scale) %>%
      mutate(
        p_fdr  = p.adjust(p_value, method = "fdr"),
        p_bonf = p.adjust(p_value, method = "bonferroni")
      ) %>%
      ungroup()
  }) %>%
    bind_rows()
}

run_item_scatter <- function(items, img_predictors, data, ncol = 3, exclude_zero = FALSE) {
  for (img_var in img_predictors) {
    cat("\n### Imaging predictor:", img_var, "\n")
    plot_data <- if (exclude_zero) data %>% filter(.data[[img_var]] != 0) else data
    plots <- map(items, function(item) {
      ggplot(plot_data, aes_string(x = img_var, y = item)) +
        geom_point(alpha = 0.6, size = 1.5) +
        geom_smooth(method = "lm", se = TRUE) +
        labs(x = img_var, y = item) +
        theme_classic(base_size = 9)
    })
    print(wrap_plots(plots, ncol = ncol))
  }
}

# ============================================================
# SUMMARY / TABLE HELPERS
# ============================================================

make_dep_summary <- function(results, scale_label, type_label) {
  results %>%
    mutate(scale = scale_label, analysis_type = type_label) %>%
    select(scale, analysis_type, outcome, imaging_measure, statistic, d, p_value, p_fdr, n)
}

print_dep_table <- function(data, caption_label) {
  data %>%
    arrange(p_value) %>%
    mutate(
      t_stat  = round(statistic, 2),
      d_val   = round(d, 2),
      p_value = round(p_value, 4),
      p_fdr   = round(p_fdr, 4),
      fdr_sig = ifelse(p_fdr < 0.05, "*", "")
    ) %>%
    select(scale, analysis_type, outcome, imaging_measure, t_stat, d_val, p_value, p_fdr, fdr_sig, n) %>%
    kable(col.names = c("Scale", "Analysis", "Outcome", "Predictor", "T", "d", "p", "p-FDR", "FDR*", "N"),
          caption = caption_label) %>%
    kable_styling(bootstrap_options = c("striped", "condensed"), font_size = 11) %>%
    print()
}

# format helper: "t(p), d=X.XX*" with * if FDR < 0.05
fmt_tp <- function(t, p, fdr, n) {
  stars <- ifelse(!is.na(fdr) & fdr < 0.05, "*", "")
  df <- n - 3
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
    select(outcome, statistic, p_value, p_fdr, n) %>%
    mutate(cell = fmt_tp(statistic, p_value, p_fdr, n)) %>%
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

fmt_tp_nostar <- function(t, p, n) {
  df <- n - 3
  partial_r <- t / sqrt(t^2 + df)
  d <- 2 * partial_r / sqrt(1 - partial_r^2)
  ifelse(is.na(t), "—",
         paste0(sprintf("%.2f", t), " (", sprintf("%.3f", p), "), d=", sprintf("%.2f", d)))
}

make_col_nostar <- function(results, predictor) {
  results %>%
    filter(imaging_measure == predictor) %>%
    select(outcome, statistic, p_value, n) %>%
    mutate(cell = fmt_tp_nostar(statistic, p_value, n)) %>%
    select(outcome, cell)
}

make_prl_dep_summary <- function(results, scale_label, analysis_type) {
  results %>%
    mutate(scale = scale_label, analysis = analysis_type) %>%
    select(scale, analysis, outcome, imaging_measure, statistic, p_value, p_fdr, n)
}

print_prl_table <- function(data, caption_label) {
  data %>%
    arrange(p_value) %>%
    mutate(
      t_stat  = round(statistic, 2),
      p_value = round(p_value, 4),
      p_fdr   = round(p_fdr, 4),
      fdr_sig = ifelse(p_fdr < 0.05, "*", "")
    ) %>%
    select(scale, outcome, imaging_measure, t_stat, p_value, p_fdr, fdr_sig, n) %>%
    kable(col.names = c("Scale", "Outcome", "Predictor", "T", "p", "p-FDR", "FDR*", "N"),
          caption = caption_label) %>%
    kable_styling(bootstrap_options = c("striped", "condensed"), font_size = 11) %>%
    print()
}

# ============================================================
# DEMOGRAPHICS / GROUP COMPARISONS
# ============================================================

sex_ttest <- function(data, vars, var_labels) {
  map2_dfr(vars, var_labels, function(v, lbl) {
    f <- data[[v]][data$test_sessions_v.gender == "F" & !is.na(data[[v]])]
    m <- data[[v]][data$test_sessions_v.gender == "M" & !is.na(data[[v]])]
    f <- f[!is.nan(f)]
    m <- m[!is.nan(m)]
    if (length(f) < 3 || length(m) < 3) return(NULL)
    tt <- t.test(f, m)
    tibble(
      variable = lbl,
      n_F      = length(f),
      mean_F   = round(mean(f, na.rm = TRUE), 3),
      sd_F     = round(sd(f,   na.rm = TRUE), 3),
      n_M      = length(m),
      mean_M   = round(mean(m, na.rm = TRUE), 3),
      sd_M     = round(sd(m,   na.rm = TRUE), 3),
      t        = round(tt$statistic, 2),
      df       = round(tt$parameter, 1),
      p        = round(tt$p.value, 4)
    )
  })
}

#takes a df and spits out a demo table
summarise_demo <- function(data, label) {
  n       <- nrow(data)
  age_m   <- round(mean(data$test_sessions_v.age, na.rm = TRUE), 1)
  age_sd  <- round(sd(data$test_sessions_v.age,   na.rm = TRUE), 1)
  pct_f   <- round(mean(data$test_sessions_v.gender == "F", na.rm = TRUE) * 100, 1)
  n_f     <- sum(data$test_sessions_v.gender == "F", na.rm = TRUE)
  n_m     <- sum(data$test_sessions_v.gender == "M", na.rm = TRUE)

  # Handedness
  pct_r  <- round(mean(data$test_sessions_v.handedness == "R", na.rm = TRUE) * 100, 1)

  tibble(
    Group            = label,
    N                = n,
    `Age mean (SD)`  = paste0(age_m, " (", age_sd, ")"),
    `% Female (n)`   = paste0(pct_f, "% (", n_f, "F / ", n_m, "M)"),
    `% Right-handed` = paste0(pct_r, "%")
  )
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

make_domain_plot <- function(type_label, title_label, domain_plot_data, ylim_shared) {
  dat <- domain_plot_data %>% filter(type == type_label)
  ggplot(dat, aes(x = domain_short, y = mean_z, fill = domain_short)) +
    geom_bar(stat = "identity", width = 0.6) +
    geom_errorbar(aes(ymin = mean_z - sd_z / sqrt(n),
                      ymax = mean_z + sd_z / sqrt(n)), width = 0.2) +
    geom_text(aes(label = sig_label,
                  y = ifelse(mean_z < 0,
                             mean_z - sd_z / sqrt(n) - 0.05,
                             mean_z + sd_z / sqrt(n) + 0.05)),
              size = 4, vjust = ifelse(dat$mean_z < 0, 1, 0)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    scale_fill_manual(values = c("EF" = "#6ec7c8", "CC" = "#bee5ce",
                                 "Mem" = "#a8d8ea", "Soc" = "#f9c7c8")) +
    labs(title = title_label, y = "Mean Z-score", x = NULL) +
    coord_cartesian(ylim = ylim_shared) +
    theme_classic(base_size = 12) +
    theme(legend.position = "none")
}

run_task_ttests <- function(task_cols, task_names, type_label, cog_domains_data) {
  map2_dfr(task_cols, task_names, function(col, nm) {
    x <- cog_domains_data[[col]]
    x_clean <- x[!is.na(x)]
    if (length(x_clean) < 5) return(NULL)
    tt <- t.test(x_clean, mu = 0)
    d  <- mean(x_clean) / sd(x_clean)
    tibble(
      type     = type_label,
      task     = nm,
      n        = length(x_clean),
      mean_z   = round(mean(x_clean), 3),
      sd_z     = round(sd(x_clean), 3),
      t        = round(tt$statistic, 2),
      df       = round(tt$parameter, 0),
      p        = round(tt$p.value, 4),
      cohens_d = round(d, 2)
    )
  })
}

make_task_plot <- function(type_label, fill_color, title_label, task_plot_data) {
  dat <- task_plot_data %>% filter(type == type_label)
  ggplot(dat, aes(x = task, y = mean_z)) +
    geom_bar(stat = "identity", fill = fill_color, width = 0.7) +
    geom_errorbar(aes(ymin = mean_z - se, ymax = mean_z + se), width = 0.25) +
    geom_text(aes(label = fdr_sig, y = star_y), size = 4) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    labs(title = title_label, y = "Mean Z-score", x = NULL) +
    coord_cartesian(ylim = c(-2, 1)) +
    theme_classic(base_size = 10) +
    theme(axis.text.x  = element_text(angle = 45, hjust = 1),
          plot.title    = element_text(hjust = 0.5),
          axis.line     = element_line(size = 1))
}

make_task_sex_plot <- function(type_label, title_label, task_sex_plot_data) {
  dat <- task_sex_plot_data %>% filter(type == type_label)
  ggplot(dat, aes(x = variable, y = mean_z, fill = test_sessions_v.gender)) +
    geom_bar(stat = "identity", position = position_dodge(0.7), width = 0.65) +
    geom_errorbar(aes(ymin = mean_z - se, ymax = mean_z + se),
                  position = position_dodge(0.7), width = 0.2) +
    geom_text(data = dat %>% filter(test_sessions_v.gender == "F"),
              aes(label = fdr_sig, y = star_y), size = 4) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    scale_fill_manual(values = c("F" = "#e8a0bf", "M" = "#7eb3d8"),
                      labels = c("F" = "Female", "M" = "Male")) +
    labs(y = "Mean Z-score", x = NULL, fill = "Sex", title = title_label) +
    coord_cartesian(ylim = c(-2.5, 1)) +
    theme_classic(base_size = 10) +
    theme(axis.text.x    = element_text(angle = 45, hjust = 1),
          plot.title      = element_text(hjust = 0.5),
          legend.position = "right")
}

make_imaging_sex_plot <- function(var_labels, title_label, imaging_sex_plot_data, y_label = "Mean Value") {
  dat <- imaging_sex_plot_data %>% filter(variable %in% var_labels)
  ggplot(dat, aes(x = variable, y = mean_val, fill = test_sessions_v.gender)) +
    geom_bar(stat = "identity", position = position_dodge(0.7), width = 0.65) +
    geom_errorbar(aes(ymin = mean_val - se, ymax = mean_val + se),
                  position = position_dodge(0.7), width = 0.2) +
    geom_text(data = dat %>% filter(test_sessions_v.gender == "F"),
              aes(label = fdr_sig, y = star_y), size = 4, hjust = 0.5) +
    scale_fill_manual(values = c("F" = "#e8a0bf", "M" = "#7eb3d8"),
                      labels = c("F" = "Female", "M" = "Male")) +
    labs(y = y_label, x = NULL, fill = "Sex", title = title_label) +
    theme_classic(base_size = 11) +
    theme(axis.text.x    = element_text(angle = 30, hjust = 1),
          plot.title      = element_text(hjust = 0.5),
          legend.position = "right")
}

# ============================================================
# MIXED-MODEL SPECIFICITY TEST
# ============================================================

# outcome ~ prop_injured * network_type + age + sex + (1 | subject); interaction term
# (prop_injured:network_type) is the specificity test. p < .05 on the LRT means the
# dep-net and nondep-net slopes differ significantly (genuine specificity evidence);
# p >= .05 means there's no statistical support for the depression network being "more
# predictive" than the non-depression network -- treat any gap between their separate
# slopes as noise, not a specificity finding.

test_specificity <- function(data, outcome_var) {

  long <- data %>%
    select(bblid, all_of(outcome_var), test_sessions_v.age, test_sessions_v.gender,
           dep_net_prop_injured, nondep_net_prop_injured) %>%
    na.omit() %>%
    pivot_longer(
      cols      = c(dep_net_prop_injured, nondep_net_prop_injured),
      names_to  = "network_type",
      values_to = "prop_injured"
    ) %>%
    mutate(
      network_type = factor(network_type,
                             levels = c("nondep_net_prop_injured", "dep_net_prop_injured")),
      outcome = .data[[outcome_var]],
      subject = as.factor(bblid),
      # prop_injured (a proportion, near-zero scale) and age (tens) are wildly different
      # magnitudes -- left raw, that ill-conditioning is what made lme4 fail to converge
      # ("very large eigenvalue -- Rescale variables?") and broke lmerTest's Satterthwaite
      # Hessian ("Downdated VtV is not positive definite"). Z-scoring both fixes the fit;
      # the LRT p-value is invariant to this linear rescaling, so the test itself is unchanged.
      prop_injured_z = as.numeric(scale(prop_injured)),
      age_z          = as.numeric(scale(test_sessions_v.age))
    )

  model_control <- lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))

  # Full model: interaction term is the specificity test
  m_full <- lmer(
    outcome ~ prop_injured_z * network_type + age_z + test_sessions_v.gender + (1 | subject),
    data = long, REML = FALSE, control = model_control
  )

  # Reduced model: no interaction (assumes same slope in both networks)
  m_reduced <- lmer(
    outcome ~ prop_injured_z + network_type + age_z + test_sessions_v.gender + (1 | subject),
    data = long, REML = FALSE, control = model_control
  )

  lrt_result   <- anova(m_reduced, m_full)   # LRT for the interaction term
  coef_summary <- summary(m_full)$coefficients
  int_term     <- "prop_injured_z:network_typedep_net_prop_injured"

  list(
    outcome          = outcome_var,
    n_subjects       = n_distinct(long$subject),
    interaction_p    = lrt_result$`Pr(>Chisq)`[2],
    chisq            = lrt_result$Chisq[2],
    interaction_coef = coef_summary[int_term, ],
    full_model       = m_full,
    lrt              = lrt_result
  )
}
