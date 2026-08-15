# L0 baseline: generate each baseline variable in DAG order, conditioning each on its parents.
# Mirrors causal_examples/autoimmune/rave/rave_baseline.py. Random draws use the np_* wrappers on
# the main stream, in the same order as the Python so the two versions line up.

RAVE_SITES <- sprintf("SITE%03d", 1:30)   # RAVE was multicenter (US + NL)

rave_make_baseline <- function(subj_num, params,
                               study_id = "RAVE",
                               study_start = as.Date("2005-01-01"),
                               enroll_window_days = 730L) {
  P <- params

  site <- np_choice(RAVE_SITES)
  patient_id <- sprintf("%s-%s-%04d", study_id, site, subj_num)

  # Demographics ----------------------------------------------------------
  country <- if (np_random() < P$p_usa) "USA" else "NLD"
  race    <- if (np_random() < 0.85) "WHITE" else np_choice(c("BLACK", "ASIAN", "OTHER"))
  sex     <- if (np_random() < P$p_female) "F" else "M"
  age     <- as.integer(clip(np_normal(P$age_mean, P$age_sd), 15, 90))
  wt      <- clip(np_normal(if (sex == "M") 80 else 68, 16), 40, 140)

  # Disease characterization ---------------------------------------------
  diagnosis_type <- if (np_random() < P$p_gpa) "GPA" else "MPA"
  anca_type      <- if (np_random() < P$p_pr3) "PR3" else "MPO"
  new_dx         <- np_random() < P$p_new_dx
  p_renal <- expit(-0.2 + (if (anca_type == "MPO") 0.5 else 0.0) + (if (diagnosis_type == "MPA") 0.4 else 0.0))
  renal   <- np_random() < p_renal

  # Disease activity / damage --------------------------------------------
  baseline_bvaswg <- clip(np_normal(P$bvaswg_mean, P$bvaswg_sd), 3, 30)
  baseline_vdi    <- as.integer(clip(round(np_normal(P$vdi_mean, P$vdi_sd)), 0, 8))

  # Comorbidities (parent: age) ------------------------------------------
  htn <- np_random() < expit(-2.5 + 0.05 * (age - 60))
  dm  <- np_random() < expit(-2.8 + 0.04 * (age - 60))

  # Frailties (drawn once) ------------------------------------------------
  fr <- draw_frailties()

  # Baseline labs (parents: sex, renal, frailty) -------------------------
  base_wbc   <- clip(np_normal(P$wbc_mean, P$wbc_sd) + 0.4 * fr$f_heme, P$wbc_floor, 16)
  base_anc   <- clip(P$anc_frac * base_wbc + np_normal(0, 0.8), 1.5, 10)
  base_hgb   <- clip(np_normal(if (sex == "M") 13.5 else 12.3, 1.3) - (if (renal) 0.8 else 0) + 0.3 * fr$f_heme, 8.5, 17.5)
  base_plt   <- clip(np_normal(P$plt_mean, P$plt_sd), P$plt_floor, 600)
  base_creat <- clip(np_normal(0.9 + (if (renal) 0.8 else 0.0), 0.3) + 0.004 * (age - 55), 0.5, 4.0)
  base_bun   <- clip(np_normal(15 + (if (renal) 12 else 0), 6), 5, 80)
  base_crp   <- clip(np_normal(2.0 + 0.5 * baseline_bvaswg, 4), 0.1, 60)
  base_esr   <- clip(np_normal(20 + 2.5 * baseline_bvaswg, 18), 2, 130)

  # Treatment assignment (randomized 1:1, independent of the other variables) ---------------------
  is_rtx <- np_random() < 0.5
  arm    <- if (is_rtx) "Rituximab" else "Control"

  # Hidden remission propensity, as log-odds ----------------------------------
  rp <- (P$remit_intercept + P$remit_rtx * is_rtx
         + P$remit_relapsing * (if (new_dx) 0 else 1)
         + P$remit_pr3 * (if (anca_type == "PR3") 1 else 0)
         + P$remit_bvas * (baseline_bvaswg - 8.0))

  enrollment_offset <- np_integers(0L, enroll_window_days)
  baseline_date <- study_start + enrollment_offset

  ct_rec(
    patient_id = patient_id, site = site, arm = arm, is_rtx = is_rtx,
    baseline_date = baseline_date, enrollment_offset_days = enrollment_offset,
    age = age, sex = sex, race = race, country = country, weight_kg = wt,
    diagnosis_type = diagnosis_type, anca_type = anca_type, new_diagnosis = new_dx,
    renal_involvement = renal,
    baseline_bvaswg = baseline_bvaswg, baseline_vdi = baseline_vdi,
    htn = htn, dm = dm,
    baseline_wbc = base_wbc, baseline_anc = base_anc, baseline_hgb = base_hgb,
    baseline_plt = base_plt, baseline_creat = base_creat, baseline_bun = base_bun,
    baseline_crp = base_crp, baseline_esr = base_esr,
    frailties = fr, remit_propensity = rp,
    # fields filled in later by the trajectory + endpoint steps ----------------------------
    remission_day = NULL, trajectory = list(),
    cr_6mo = 0L, time_to_remission_day = NULL, time_to_cr_day = NULL,
    flare_event = 0L, flare_day = NULL, remission_duration_day = NULL,
    serious_ae = 0L, crossover_day = NULL,
    discontinuation_day = NULL, discontinuation_visit_day = NULL, discontinuation_reason = NULL,
    death_day = NULL, disposition = "COMPLETED", last_contact_day = RAVE_ADMIN_CENSOR_DAY
  )
}
