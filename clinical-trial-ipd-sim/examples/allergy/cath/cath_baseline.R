# L0 — generates the CATH baseline nodes, in DAG order. Ported from
# causal_examples/allergy/cath/cath_baseline.py. The diagnosis GROUP is a baseline stratum drawn
# from a cited category prior (the posted group counts); the treatment arm is randomized 1:1
# WITHIN each group (not a single coin-flip across the whole sample). Frailties are drawn once, here.

CATH_STUDY_START <- as.Date("2009-03-01")
CATH_ENROLL_WINDOW_DAYS <- 730L
MH_CANDIDATES <- c("Seasonal allergy", "Asthma", "Hypercholesterolaemia",
                   "Gastrooesophageal reflux disease", "Migraine")
CM_CANDIDATES <- list(c("ACETAMINOPHEN", "Headache"), c("IBUPROFEN", "Musculoskeletal pain"),
                      c("LORATADINE", "Allergic rhinitis"), c("CETIRIZINE", "Allergic rhinitis"))

cath_make_baseline <- function(subj_num, P, study_id = "CATH") {
  site <- "UCSD"
  patient_id <- sprintf("%s-%s-%04d", study_id, site, subj_num)

  group <- cath_cat(P$p_diagnosis_group)               # the main baseline stratum (observed, not randomized)

  # ---- demographics ----
  sex <- if (np_random() < P$p_female) "F" else "M"
  ag <- P$age_by_group[[group]]
  age <- as.integer(clip(round(np_normal(ag[1], ag[2])), P$age_clip[1], P$age_clip[2]))
  race <- cath_cat(P$p_race)
  ethnic <- if (np_random() < P$p_hispanic) "HISPANIC OR LATINO" else "NOT HISPANIC OR LATINO"
  fitz <- cath_cat(P$p_fitzpatrick)
  country <- if (np_random() < P$p_usa) "USA" else "OTHER"
  hs <- P$height_by_sex_cm[[sex]]; height <- clip(np_normal(hs[1], hs[2]), 140, 205)
  bg <- P$bmi_by_group[[group]]; bmi <- clip(np_normal(bg[1], bg[2]), 16, 45)
  weight <- bmi * (height / 100.0)^2

  # ---- treatment arm (randomized 1:1 within group) ----
  is_vitd <- np_random() < P$p_arm_vitd
  arm <- if (is_vitd) "Vitamin D3" else "Placebo"

  # ---- disease characterization ----
  if (group == "Psor") {
    dx_psoriasis <- "PLAQUE PSORIASIS"
    psor_duration <- P$psor_duration_min_mo + np_exponential(P$psor_duration_excess_mean_mo)
    psor_severity <- cath_cat(P$psor_severity_probs)
  } else { dx_psoriasis <- ""; psor_duration <- NULL; psor_severity <- "" }

  fr <- cath_draw_frailties(P)   # frailties, drawn once per patient

  # ---- baseline serum labs (V1) ----
  vg <- P$vitd_bl_by_group[[group]]; dark <- if (fitz %in% DARK_FITZ) 1.0 else 0.0
  vitd_bl <- clip(np_normal(vg[1], vg[2]) + P$vitd_bl_darkskin_coef * (dark - 0.39) + P$vitd_bl_bmi_coef * (bmi - bg[1]), 5, 80)
  cg <- P$calcium_bl_by_group[[group]]; calcium_bl <- clip(np_normal(cg[1], cg[2]), P$calcium_clip[1], P$calcium_clip[2])
  crg <- P$creat_bl_by_group[[group]]; creat_bl <- clip(np_normal(crg[1], crg[2]), P$creat_clip[1], P$creat_clip[2])
  pg <- P$pth_bl_by_group[[group]]; pth_bl <- clip(np_normal(pg[1], pg[2]) + P$pth_vitd_coupling * (vitd_bl - 29.0), 15, 75)
  ig <- P$ige_bl_lognormal_by_group[[group]]; ige_bl <- clip(exp(np_normal(log(ig[1]), ig[2])), 1, 20000)
  z_logige <- (log(ige_bl) - 4.0) / 1.5
  rl <- P$rast_logit
  p_rast <- expit(rl$intercept + rl$ad_coef * (if (group == "AD") 1 else 0) + rl$logige_z_coef * z_logige)
  rast_bl <- if (np_random() < p_rast) "POSITIVE" else "NEGATIVE"
  serumstor <- "stored"

  # ---- baseline skin substrate (V2): TH2 -> AMP -> microbes ----
  noise <- P$substrate_noise_sd
  camp_bl <- list(); hbd3_bl <- list(); il13_bl <- list(); il4_bl <- list(); cfu_bl <- list()
  camp_int <- P$camp_bl_intercept_by_group[[group]]; hbd3_int <- P$hbd3_bl_intercept_by_group[[group]]
  th2_int <- P$th2_bl_intercept_by_group[[group]]; cfu_int <- P$cfu_bl_intercept_by_group[[group]]
  lam <- P$camp_bl_lesional_offset; th2lam <- P$th2_bl_lesional_offset; theta <- P$camp_th2_suppression_coef
  for (c in c("lesional", "nonlesional")) {
    les <- if (c == "lesional") 1.0 else 0.0
    th2_tone <- th2_int + th2lam * les + fr$f_th2
    il13_bl[[c]] <- max(0.0, th2_tone + np_normal(0, noise))
    il4_bl[[c]]  <- max(0.0, P$il4_lesional_scale * th2_tone + np_normal(0, noise))
    camp_bl[[c]] <- max(0.0, camp_int + lam * les - theta * th2_tone + fr$f_amp + np_normal(0, noise))
    hbd3_bl[[c]] <- max(0.0, hbd3_int + lam * les - theta * th2_tone + fr$f_amp + np_normal(0, noise))
    cfu_bl[[c]]  <- cfu_int - P$cfu_amp_coef * camp_bl[[c]] + fr$f_microbiome + np_normal(0, P$cfu_noise_sd)
  }
  g0 <- P$ts_amp_gamma$gamma0; g1 <- P$ts_amp_gamma$gamma1
  ts_bl <- list(
    TS_CAMP_LES    = max(0.0, g0 + g1 * camp_bl[["lesional"]]    + 0.3 * fr$f_amp + np_normal(0, noise)),
    TS_CAMP_NONLES = max(0.0, g0 + g1 * camp_bl[["nonlesional"]] + 0.3 * fr$f_amp + np_normal(0, noise)),
    TS_HBD3_LES    = max(0.0, g0 + g1 * hbd3_bl[["lesional"]]    + 0.3 * fr$f_amp + np_normal(0, noise)),
    TS_HBD3_NONLES = max(0.0, g0 + g1 * hbd3_bl[["nonlesional"]] + 0.3 * fr$f_amp + np_normal(0, noise)))
  amp_tone <- 0.5 * (camp_bl[["lesional"]] + camp_bl[["nonlesional"]])
  hbd_tone <- 0.5 * (hbd3_bl[["lesional"]] + hbd3_bl[["nonlesional"]])
  tp <- P$sal_totprot_mean_sd; sal_totprot <- clip(np_normal(tp[1], tp[2]), 0.2, 3.0)
  sal_bl <- list(
    SAL_CAMP = max(0.0, P$sal_amp_beta1 * amp_tone + fr$f_amp + np_normal(0, noise)),
    SAL_HBD3 = max(0.0, P$sal_amp_beta1 * hbd_tone + fr$f_amp + np_normal(0, noise)),
    SAL_TOTPROT = sal_totprot)
  colonized <- (cfu_bl[["lesional"]] > 5.0) || (fr$f_microbiome > 0.6)
  sw_flora_bl <- if (colonized) "S. aureus predominant" else "Mixed commensal flora"

  # ---- exposure (Layer A): capsule counts + chance a capsule goes unreturned ----
  q_cap <- expit(P$ex_return_logit_intercept + P$ex_return_dropout_coef * fr$f_dropout)
  ex_ndisp <- P$ex_ncapsule
  ex_nret <- np_binomial(ex_ndisp, q_cap)
  ex_compliance <- clip(100.0 * (ex_ndisp - ex_nret) / P$ex_days, 0, 100)
  drug_not_returned <- np_random() < q_cap

  # ---- medical history / concomitant meds ----
  p_mh <- expit(P$mh_logit_intercept + P$mh_age_slope * (age - 40))
  mh_items <- list()
  for (t in MH_CANDIDATES) if (np_random() < p_mh) mh_items[[length(mh_items) + 1L]] <- list(MHTERM = t, MHOCCUR = "Y")
  cm_items <- list()
  if (np_random() < P$cm_prevalence) {
    cc <- CM_CANDIDATES[[np_integers(0L, length(CM_CANDIDATES)) + 1L]]
    cm_items[[1L]] <- list(CMTRT = cc[1], CMINDC = cc[2], CMSTOFFSET = np_integers(30L, 400L), CMONGO = "Y")
  }
  baseline_date <- CATH_STUDY_START + np_integers(0L, CATH_ENROLL_WINDOW_DAYS)

  ct_rec(
    patient_id = patient_id, site = site, arm = arm, is_vitd = is_vitd,
    diagnosis_group = group, baseline_date = baseline_date,
    age = age, sex = sex, race = race, ethnic = ethnic, country = country,
    fitzpatrick = fitz, height_cm = height, weight_kg = weight, bmi = bmi,
    dx_psoriasis = dx_psoriasis, psor_duration_mo = psor_duration, psor_severity = psor_severity,
    vitd_bl = vitd_bl, calcium_bl = calcium_bl, creat_bl = creat_bl, pth_bl = pth_bl,
    ige_bl = ige_bl, rast_bl = rast_bl, serumstor = serumstor,
    camp_bl = camp_bl, hbd3_bl = hbd3_bl, il13_bl = il13_bl, il4_bl = il4_bl,
    sal_bl = sal_bl, ts_bl = ts_bl, cfu_bl = cfu_bl, sw_flora_bl = sw_flora_bl,
    ex_ndisp = ex_ndisp, ex_nret = ex_nret, ex_compliance = ex_compliance, drug_not_returned = drug_not_returned,
    frailties = fr, mh_items = mh_items, cm_items = cm_items,
    trajectory = list(), deltas = list(),
    not_completed = FALSE, disposition = "COMPLETED", discontinuation_reason = NULL,
    discontinuation_day = NULL, discontinuation_visit_day = NULL,
    last_contact_day = CATH_PRIMARY_ENDPOINT_DAY, efficacy_population = TRUE
  )
}
