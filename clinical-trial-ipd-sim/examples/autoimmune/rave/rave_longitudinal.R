# Lt: step each patient forward one visit at a time. Mirrors rave_longitudinal.py.
# Order within a visit: exposure -> prednisone -> labs -> BVAS/WG -> AEs (fixed CTCAE grading plus
# frailty/arm/infection/infusion/steroid effects) -> dose changes -> crossover/discontinuation.
# Regular draws use np_* (main stream); visit-date jitter uses its own `jit` stream.

# ---- CTCAE v3.0 grading (FIXED rules — never tuned) --------------------------------------------
leuko_grade   <- function(wbc) if (wbc >= 4.0) 0L else if (wbc >= 3.0) 1L else if (wbc >= 2.0) 2L else if (wbc >= 1.0) 3L else 4L
neutro_grade  <- function(anc) if (anc >= 1.5) 0L else if (anc >= 1.0) 1L else if (anc >= 0.5) 2L else if (anc >= 0.2) 3L else 4L
anemia_grade  <- function(hgb) if (hgb >= 10.0) 0L else if (hgb >= 8.0) 1L else if (hgb >= 6.5) 2L else 3L
thrombo_grade <- function(plt) if (plt >= 75) 0L else if (plt >= 50) 1L else if (plt >= 25) 2L else 3L

RAVE_SOC <- list(
  Leukopenia = "Blood and lymphatic system disorders", Neutropenia = "Blood and lymphatic system disorders",
  Anaemia = "Blood and lymphatic system disorders", Thrombocytopenia = "Blood and lymphatic system disorders",
  Nausea = "Gastrointestinal disorders", Vomiting = "Gastrointestinal disorders", Diarrhoea = "Gastrointestinal disorders",
  Alopecia = "Skin and subcutaneous tissue disorders", Rash = "Skin and subcutaneous tissue disorders",
  Arthralgia = "Musculoskeletal and connective tissue disorders",
  Fatigue = "General disorders", Headache = "Nervous system disorders",
  Cough = "Respiratory, thoracic and mediastinal disorders",
  Infection = "Infections and infestations",
  `Infusion related reaction` = "Immune system disorders",
  Hyperglycaemia = "Metabolism and nutrition disorders",
  Cushingoid = "Endocrine disorders", Insomnia = "Psychiatric disorders",
  `Vasculitis-related event` = "Other"
)
STEROID_AES <- c("Hyperglycaemia", "Cushingoid", "Insomnia")
SEV_WORD    <- c("MILD", "MODERATE", "SEVERE", "LIFE-THREATENING")

# build one AE record as an environment so reconcile_ae_ds can change AEACN in place later. onset_day is issue #182.
rave_ae <- function(patient, name, grade, related, action, day, key, serious = NULL, onset_day = NULL) {
  info <- visit_info(key)
  recorded <- if (!is.null(onset_day)) onset_day else day
  vd <- rave_visit_date(patient$baseline_date, recorded)
  g <- max(1L, min(grade, 4L))
  ser <- if (!is.null(serious)) serious else (grade >= 3)
  ct_rec(
    USUBJID = patient$patient_id, VISIT = key, VISITLBL = info$VISIT %||% key,
    VISITNUM = info$VISITNUM %||% 0L, AEDY = recorded, AESTDTC = format(vd, "%Y-%m-%d"),
    AETERM = name, AEDECOD = toupper(name), AEBODSYS = RAVE_SOC[[name]] %||% "Other",
    AESEV = SEV_WORD[g], AETOXGR = grade, AEREL = related, AEACN = action,
    AESER = if (ser) "Y" else "N",
    AEOUT = if (grade >= 3) "RECOVERING" else "RECOVERED", AEENDTC = ""
  )
}

# prednisone taper per protocol: start ~1 mg/kg/day, reach 0 by day 180 if heading to complete remission
rave_prednisone <- function(day, weight, cr6, P) {
  start <- P$pred_start_mgkg * weight
  end_day <- P$pred_taper_end_day
  if (day <= 1) return(as.numeric(round(start)))
  if (day >= end_day) return(if (cr6) 0.0 else 7.5)
  frac <- 1.0 - (day - 1) / (end_day - 1)
  floor_dose <- if (cr6) 0.0 else 7.5
  as.numeric(round(max(floor_dose, start * frac)))
}

.rave_next_nom <- function(day) { for (s in RAVE_SCHED) if (s$day > day) return(s$day); RAVE_ADMIN_CENSOR_DAY + 1L }

rave_simulate_trajectory <- function(sim, patient, jit) {
  P <- sim$params; fr <- patient$frailties; is_rtx <- patient$is_rtx

  # ---- decide the patient's disease course up front ----
  remit_ever <- np_random() < 0.93
  cr6 <- (np_random() < expit(patient$remit_propensity)) && remit_ever
  if (remit_ever) rday <- as.integer(clip(exp(np_normal(log(P$remit_day_median), P$remit_day_sigma)), 8, 175)) else rday <- 1e9
  patient$remission_day <- if (remit_ever) rday else NULL

  wbc <- patient$baseline_wbc; anc <- patient$baseline_anc
  hgb <- patient$baseline_hgb; plt <- patient$baseline_plt
  creat <- patient$baseline_creat; bun <- patient$baseline_bun
  crp <- patient$baseline_crp; esr <- patient$baseline_esr
  bvas <- patient$baseline_bvaswg; vdi <- patient$baseline_vdi
  cum_gc <- 0.0; prev_day <- 1L; prev_actual <- 1L
  in_remission <- FALSE; discontinued <- FALSE; crossed <- FALSE
  ae_hist <- setNames(as.list(rep(FALSE, length(P$ae_nonlab))), names(P$ae_nonlab))
  traj <- list()

  for (s in RAVE_SCHED) {
    key <- s$key; num <- s$visitnum; day <- s$day
    if (identical(key, "SCRN")) next
    if (day > RAVE_ADMIN_CENSOR_DAY) break
    if (discontinued) break

    interval_start <- prev_day
    next_nom <- .rave_next_nom(day)
    actual_day <- sim$clamp_actual_day(jit, day, prev_actual, next_nom, P$visit_jitter_sd_day)

    # 1. exposure
    rtx_infusion    <- is_rtx && (key %in% RTX_INFUSION_VISITS)
    rtx_placebo_inf <- (!is_rtx) && (key %in% RTX_INFUSION_VISITS)
    cyc_active <- (!is_rtx) && (day >= 1 && day <= 90)
    aza_active <- (!is_rtx) && (day > 90)

    # 2. prednisone
    pred <- rave_prednisone(day, patient$weight_kg, cr6, P)
    cum_gc <- cum_gc + pred * max(1L, day - prev_day)

    # 3. labs
    wbc_drag <- if (cyc_active) P$wbc_cyc_drag + P$wbc_cyc_drag_frailty * fr$f_heme
                else if (is_rtx) P$wbc_rtx_drag + P$wbc_rtx_drag_frailty * fr$f_heme
                else if (aza_active) 0.6 + 0.3 * fr$f_heme else 0.0
    wbc <- P$wbc_ar * wbc + (1 - P$wbc_ar) * patient$baseline_wbc - wbc_drag + np_normal(0, P$wbc_noise)
    wbc <- clip(wbc, 0.3, 18)
    anc <- clip(P$anc_frac * wbc + np_normal(0, P$anc_noise), 0.1, 12)
    hgb <- clip(P$hgb_ar * hgb + (1 - P$hgb_ar) * patient$baseline_hgb
                - (if (cyc_active) P$hgb_cyc_drag + 0.2 * fr$f_heme else 0.0) + np_normal(0, P$hgb_noise), 6.0, 17.5)
    plt <- clip(P$plt_ar * plt + (1 - P$plt_ar) * patient$baseline_plt
                - (if (cyc_active) P$plt_cyc_drag + 8 * fr$f_heme else 0.0)
                - (if (rtx_infusion) P$plt_rtx_drag else 0.0) + np_normal(0, P$plt_noise), 10, 650)
    creat <- clip(0.7 * creat + 0.3 * patient$baseline_creat - 0.10 * (if (in_remission) 1 else 0) + np_normal(0, 0.06), 0.4, 5.0)
    bun <- clip(0.7 * bun + 0.3 * patient$baseline_bun + np_normal(0, 2), 4, 90)

    # 4. BVAS/WG disease activity
    flare_label <- "NONE"
    if (remit_ever && day >= rday) {
      if (!in_remission) { in_remission <- TRUE; if (is.null(patient$time_to_remission_day)) patient$time_to_remission_day <- rday }
      bvas <- 0.0
    } else {
      target <- if (remit_ever) max(0.0, patient$baseline_bvaswg * (1 - (day - 1) / max(1, rday - 1)))
                else max(2.0, patient$baseline_bvaswg * 0.45)
      bvas <- max(0.0, 0.4 * bvas + 0.6 * target + np_normal(0, 0.3))
      if (bvas < 0.5) bvas <- 0.0
    }
    # once in remission, model flares (the post-6-month maintenance phase)
    if (in_remission && bvas == 0.0 && day > max(rday, P$flare_window_start_day)) {
      log_h <- (log(P$flare_base_haz) + P$flare_rtx * is_rtx + P$flare_pr3 * (patient$anca_type == "PR3")
                + P$flare_relapsing * (if (patient$new_diagnosis) 0 else 1)
                + P$flare_pred_protect * pred + P$flare_frailty * fr$f_relapse)
      if (np_random() < min(0.6, exp(log_h))) {
        severe <- np_random() < P$p_flare_severe
        flare_label <- if (severe) "SEVERE" else "LIMITED"
        bvas <- if (severe) np_uniform(3, 8) else np_uniform(1, 3)
        in_remission <- FALSE
        vdi <- min(8, vdi + (if (severe && np_random() < 0.4) 1 else 0))
        if (is.null(patient$flare_day)) { patient$flare_day <- day; patient$flare_event <- 1L }
      }
    }
    crp <- clip(0.5 * crp + 0.5 * (1.0 + 0.6 * bvas) + np_normal(0, 1.5), 0.1, 60)
    esr <- clip(0.5 * esr + 0.5 * (8 + 2.0 * bvas) + np_normal(0, 6), 2, 130)
    hematuria <- if (patient$renal_involvement) as.integer(clip(round((bvas / 4.0) * 1.5 + np_normal(0, 0.3)), 0, 3)) else 0L
    remission_now <- (bvas == 0.0)

    # 5. AEs
    aes <- list()
    # 5a. grade the labs with the fixed CTCAE rules
    grade_specs <- list(
      list(name = "Leukopenia",       val = wbc, grader = leuko_grade,   repkey = "leuko_report"),
      list(name = "Neutropenia",      val = anc, grader = neutro_grade,  repkey = "leuko_report"),
      list(name = "Anaemia",          val = hgb, grader = anemia_grade,  repkey = "anemia_report"),
      list(name = "Thrombocytopenia", val = plt, grader = thrombo_grade, repkey = "thrombo_report")
    )
    for (gs in grade_specs) {
      g <- gs$grader(gs$val)
      if (g >= 1 && np_random() < P[[gs$repkey]][[as.character(min(g, 4L))]]) {
        rel <- if (cyc_active || aza_active || g >= 2) "RELATED" else "POSSIBLY RELATED"
        act <- if (g >= 3 && (cyc_active || aza_active)) "DOSE REDUCED" else "DOSE NOT CHANGED"
        aes[[length(aes) + 1L]] <- rave_ae(patient, gs$name, g, rel, act, day, key, serious = (g >= 4), onset_day = actual_day)
      }
    }
    # 5b. infection
    log_hi <- (log(P$infect_base_haz) + P$infect_frailty * fr$f_infect + P$infect_rtx * is_rtx
               + P$infect_cyc * (cyc_active || aza_active) + P$infect_pred * pred)
    if (np_random() < min(0.6, exp(log_hi))) {
      serious <- np_random() < P$p_infect_serious
      g <- if (serious) 3L else (if (np_random() < 0.6) 1L else 2L)
      aes[[length(aes) + 1L]] <- rave_ae(patient, "Infection", g, "POSSIBLY RELATED", "DOSE NOT CHANGED",
                                         day, key, serious = serious, onset_day = sim$between(jit, interval_start, day))
    }
    # 5b'. serious disease-related event
    if (np_random() < P$infect_base_haz_serious_disease * exp(0.5 * fr$f_relapse + P$serious_disease_rtx * is_rtx)) {
      aes[[length(aes) + 1L]] <- rave_ae(patient, "Vasculitis-related event", 3L, "NOT RELATED", "DOSE NOT CHANGED",
                                         day, key, serious = TRUE, onset_day = sim$between(jit, interval_start, day))
    }
    # 5c. infusion reaction (only on real RTX infusions)
    if (rtx_infusion && np_random() < P$infusion_rxn_haz) {
      g <- if (np_random() < 0.8) 2L else 3L
      aes[[length(aes) + 1L]] <- rave_ae(patient, "Infusion related reaction", g, "RELATED",
                                         if (g < 3) "DOSE NOT CHANGED" else "DRUG INTERRUPTED", day, key, onset_day = actual_day)
    }
    # 5d. steroid AEs
    if (pred > 0) {
      ph <- P$steroid_ae_per_mg * pred * exp(P$steroid_ae_frailty * fr$f_steroid)
      for (nm in STEROID_AES) {
        if (np_random() < min(0.5, ph)) {
          aes[[length(aes) + 1L]] <- rave_ae(patient, nm, if (np_random() < 0.8) 1L else 2L, "RELATED",
                                             "DOSE NOT CHANGED", day, key, onset_day = sim$between(jit, interval_start, day))
        }
      }
    }
    # 5e. non-lab AEs (driven by the shared frailty and the arm)
    for (name in names(P$ae_nonlab)) {
      spec <- P$ae_nonlab[[name]]
      log_h <- log(spec$base) + fr[[spec$fattr]] + spec$lrc * (cyc_active || aza_active) + spec$lrr * is_rtx
      if (isTRUE(ae_hist[[name]])) log_h <- log_h + 0.3
      if (np_random() < min(0.9, 1 - exp(-exp(log_h)))) {
        severe <- np_random() < spec$psev
        g <- if (severe) (if (np_random() < 0.85) 3L else 4L) else (if (np_random() < 0.65) 1L else 2L)
        aes[[length(aes) + 1L]] <- rave_ae(patient, name, g, "POSSIBLY RELATED", "DOSE NOT CHANGED",
                                           day, key, onset_day = sim$between(jit, interval_start, day))
        ae_hist[[name]] <- TRUE
      }
    }
    if (any(vapply(aes, function(a) identical(a$AESER, "Y"), logical(1)))) patient$serious_ae <- 1L

    # 6. dose modification
    dose_action <- "NONE"
    if ((cyc_active || aza_active) && (leuko_grade(wbc) >= 3 || neutro_grade(anc) >= 3)) dose_action <- "REDUCED"
    if ((rtx_infusion || rtx_placebo_inf) && wbc < 3.0) dose_action <- "WITHHELD"

    # save this visit's row (the aes are environments, updated later by reconcile)
    traj[[length(traj) + 1L]] <- list(
      visit_key = key, visit_day = day, actual_day = actual_day, visit_num = num,
      bvaswg = round(bvas, 1), remission = remission_now, flare = flare_label, vdi = vdi,
      prednisone_dose = pred, cum_gc = round(cum_gc, 0),
      cyc_active = cyc_active, aza_active = aza_active,
      rtx_infusion = (rtx_infusion || rtx_placebo_inf), dose_action = dose_action,
      wbc = round(wbc, 2), anc = round(anc, 2), hgb = round(hgb, 1), plt = round(plt, 0),
      creat = round(creat, 2), bun = round(bun, 0), crp = round(crp, 1), esr = round(esr, 0),
      hematuria = hematuria, aes = aes, on_treatment = !discontinued
    )
    patient$trajectory <- traj      # keep patient$trajectory current for the discontinuation logic below
    prev_day <- day; prev_actual <- actual_day

    # 7. crossover (non-responders, V5-V7) + discontinuation
    if ((!crossed) && (!remit_ever) && (key %in% c("V5", "V6", "V7")) && np_random() < P$p_crossover_nonresponse) {
      crossed <- TRUE; patient$crossover_day <- day
    }
    log_hd <- (P$disc_intercept + P$disc_frailty * fr$f_dropout
               + P$disc_serious_ae * (if (patient$serious_ae) 1 else 0)
               + P$disc_severe_flare * (if (flare_label == "SEVERE") 1 else 0))
    if (np_random() < expit(log_hd)) {
      discontinued <- TRUE
      patient$discontinuation_visit_day <- day
      patient$discontinuation_day <- if (day > interval_start) as.integer(ceiling(jit$draw(function() np_uniform(interval_start, day)))) else day
      if (flare_label == "SEVERE") {
        patient$discontinuation_reason <- "DISEASE FLARE"
      } else if (patient$serious_ae) {
        patient$discontinuation_reason <- "ADVERSE EVENT"
        ser <- unlist(lapply(traj, function(r) vapply(Filter(function(a) identical(a$AESER, "Y"), r$aes), function(a) a$AEDY, numeric(1))))
        if (length(ser)) patient$discontinuation_day <- max(patient$discontinuation_day, max(ser))
      } else {
        patient$discontinuation_reason <- np_choice(c("WITHDRAWAL BY SUBJECT", "PHYSICIAN DECISION", "OTHER"), prob = c(0.55, 0.3, 0.15))
      }
    }
  }

  patient$trajectory <- traj
  patient$cr6_latent <- cr6
  invisible(patient)
}
