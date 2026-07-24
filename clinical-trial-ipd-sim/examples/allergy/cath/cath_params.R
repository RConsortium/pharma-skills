# CATH parameters — the ONLY thing you tune. Ported from causal_examples/allergy/cath/params.py.
# The working list is BUILT FROM the Step-4 snapshot params/params_final.json (the single source of
# truth); a few coupling coefficients the DAG names but Step 4 left implicit are added as flagged
# `model` defaults. simplifyDataFrame=FALSE so [mean,sd] arrays load as numeric vectors and objects
# as named lists, never as data.frames.

cath_default_params <- function(path = NULL) {
  if (is.null(path)) path <- skill_file("examples", "allergy", "cath", "params", "params_final.json")
  raw <- jsonlite::fromJSON(paste(readLines(path, warn = FALSE), collapse = "\n"), simplifyDataFrame = FALSE)$params
  v <- function(sec, key) raw[[sec]][[key]]$value

  P <- list()
  # ---- L0 population ----
  pop <- "L0_population"
  P$p_diagnosis_group <- v(pop, "p_diagnosis_group"); P$p_female <- v(pop, "p_female")
  P$p_usa <- v(pop, "p_usa"); P$p_race <- v(pop, "p_race"); P$p_hispanic <- v(pop, "p_hispanic")
  P$p_fitzpatrick <- v(pop, "p_fitzpatrick"); P$age_by_group <- v(pop, "age_by_group")
  P$bmi_by_group <- v(pop, "bmi_by_group"); P$age_clip <- v(pop, "age_clip")
  P$height_by_sex_cm <- v(pop, "height_by_sex_cm")
  # ---- L0 disease ----
  dis <- "L0_disease"
  P$psor_duration_min_mo <- v(dis, "psor_duration_min_mo")
  P$psor_duration_excess_mean_mo <- v(dis, "psor_duration_excess_mean_mo")
  P$psor_severity_probs <- v(dis, "psor_severity_probs")
  P$mh_logit_intercept <- v(dis, "mh_logit_intercept"); P$mh_age_slope <- v(dis, "mh_age_slope")
  # ---- L0 serum labs ----
  lab <- "L0_serum_labs"
  P$vitd_bl_by_group <- v(lab, "vitd_bl_by_group"); P$vitd_bl_darkskin_coef <- v(lab, "vitd_bl_darkskin_coef")
  P$vitd_bl_bmi_coef <- v(lab, "vitd_bl_bmi_coef"); P$calcium_bl_by_group <- v(lab, "calcium_bl_by_group")
  P$calcium_clip <- v(lab, "calcium_clip"); P$creat_bl_by_group <- v(lab, "creat_bl_by_group")
  P$creat_clip <- v(lab, "creat_clip"); P$pth_bl_by_group <- v(lab, "pth_bl_by_group")
  P$pth_vitd_coupling <- v(lab, "pth_vitd_coupling")
  P$ige_bl_lognormal_by_group <- v(lab, "ige_bl_lognormal_by_group"); P$rast_logit <- v(lab, "rast_logit")
  # ---- L0 cutaneous substrate ----
  cut <- "L0_cutaneous_substrate"
  P$camp_bl_intercept_by_group <- v(cut, "camp_bl_intercept_by_group")
  P$camp_bl_lesional_offset <- v(cut, "camp_bl_lesional_offset")
  P$camp_th2_suppression_coef <- v(cut, "camp_th2_suppression_coef")
  P$hbd3_bl_intercept_by_group <- v(cut, "hbd3_bl_intercept_by_group")
  P$th2_bl_intercept_by_group <- v(cut, "th2_bl_intercept_by_group")
  P$th2_bl_lesional_offset <- v(cut, "th2_bl_lesional_offset")
  P$sal_amp_beta1 <- v(cut, "sal_amp_beta1"); P$sal_totprot_mean_sd <- v(cut, "sal_totprot_mean_sd")
  P$ts_amp_gamma <- v(cut, "ts_amp_gamma"); P$cfu_bl_intercept_by_group <- v(cut, "cfu_bl_intercept_by_group")
  P$cfu_amp_coef <- v(cut, "cfu_amp_coef"); P$substrate_noise_sd <- v(cut, "substrate_noise_sd")
  # ---- L0 frailty SDs ----
  for (k in c("sigma_f_amp", "sigma_f_th2", "sigma_f_vitd_resp", "sigma_f_microbiome", "sigma_f_ae", "sigma_f_dropout"))
    P[[k]] <- v("L0_frailties", k)
  # ---- A treatment ----
  trt <- "A_treatment"
  P$p_arm_vitd <- v(trt, "p_arm_vitd"); P$ex_dose_iu <- v(trt, "ex_dose_iu")
  P$ex_ncapsule <- 24L; P$ex_days <- 21L
  P$ex_return_logit_intercept <- v(trt, "ex_return_logit_intercept")
  P$ex_return_dropout_coef <- v(trt, "ex_return_dropout_coef")
  # ---- Lt mediator / safety ----
  med <- "Lt_mediator_safety"
  P$vitd_d21_delta_full_compliance <- v(med, "vitd_d21_delta_full_compliance")
  P$vitd_d21_resp_coef <- v(med, "vitd_d21_resp_coef"); P$vitd_d21_noise_sd <- v(med, "vitd_d21_noise_sd")
  P$calcium_d21_ar <- v(med, "calcium_d21_ar"); P$calcium_d21_vitd_bump <- v(med, "calcium_d21_vitd_bump")
  P$creat_d21_ar <- v(med, "creat_d21_ar"); P$pth_d21_ar <- v(med, "pth_d21_ar")
  P$pth_d21_vitd_coupling <- v(med, "pth_d21_vitd_coupling"); P$vitals_ar <- v(med, "vitals_ar")
  P$vitals_norms <- v(med, "vitals_norms")
  P$pe_abnormal_skin_prob_by_group <- v(med, "pe_abnormal_skin_prob_by_group")
  P$pasi_by_severity <- v(med, "pasi_by_severity"); P$pasi_vitd_delta <- v(med, "pasi_vitd_delta")
  P$pasi_noise_sd <- v(med, "pasi_noise_sd")
  # ---- Lt calibrated endpoint substrate (the 30 posted change cells) ----
  cal <- raw$Lt_endpoint_substrate_CALIBRATED
  P$camp_change <- cal$camp_change; P$hbd3_change <- cal$hbd3_change; P$il13_change <- cal$il13_change
  # ---- Lt uncalibrated endpoint substrate ----
  unc <- "Lt_endpoint_substrate_UNCALIBRATED"
  for (k in c("il4_change_vitd_delta", "il4_change_sd", "sal_amp_vitd_delta", "ts_amp_vitd_delta",
              "cfu_d21_ar", "cfu_amp_change_coef", "cfu_noise_sd", "ige_d21_ar",
              "rast_d21_flip_prob", "sw_flora_change_prob"))
    P[[k]] <- v(unc, k)
  # ---- Lt adverse events ----
  ae <- "Lt_adverse_events_CALIBRATED"
  P$ae_base_haz_vd_gi <- v(ae, "ae_base_haz_vd_gi"); P$ae_base_haz_procedural <- v(ae, "ae_base_haz_procedural")
  P$ae_rr_vd <- v(ae, "ae_rr_vd"); P$ae_frailty_coef <- v(ae, "ae_frailty_coef"); P$ae_p_severe <- v(ae, "ae_p_severe")
  # ---- Lt disposition ----
  dsp <- "Lt_disposition_CALIBRATED"
  P$disc_logit_intercept <- v(dsp, "disc_logit_intercept"); P$disc_dropout_coef <- v(dsp, "disc_dropout_coef")
  P$disc_drugreturn_coef <- v(dsp, "disc_drugreturn_coef"); P$disc_reason_probs <- v(dsp, "disc_reason_probs")
  # ---- admin / con-meds ----
  adm <- "Admin_and_conmeds"
  P$site_single_center <- v(adm, "site_single_center"); P$photo_taken <- v(adm, "photo_taken")
  P$preg_result <- v(adm, "preg_result"); P$cm_prevalence <- v(adm, "cm_prevalence")
  P$swcollect_prob <- v(adm, "swcollect_prob")
  # ---- coupling coefficients (model defaults for DAG edges) ----
  P$visit_jitter_sd_day <- 2.0; P$amp_change_resp_coef <- 0.6; P$il13_th2_coupling <- 0.3
  P$il4_lesional_scale <- 0.7; P$vitals_age_slope_sysbp <- 0.3; P$ige_change_noise_sd <- 0.05
  P
}
