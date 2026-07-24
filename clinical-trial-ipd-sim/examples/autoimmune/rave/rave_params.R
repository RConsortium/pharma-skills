# RAVE simulator parameters — the only things the Step-6 calibration loop is allowed to change.
# Mirrors causal_examples/autoimmune/rave/params.py. Calibration tunes these values but never the
# model's structure. Validation only checks the values; it never swaps them out.

RAVE_DEFAULT_PARAMS <- list(
  # ---- L0 baseline population (from ClinicalTrials.gov baseline characteristics) ----
  p_female = 0.492, age_mean = 52.8, age_sd = 15.5, p_usa = 0.92,
  p_gpa = 0.75, p_pr3 = 0.66, p_new_dx = 0.50,
  bvaswg_mean = 8.0, bvaswg_sd = 3.1, vdi_mean = 1.2, vdi_sd = 1.7,
  wbc_mean = 8.0, wbc_sd = 2.2, wbc_floor = 4.0,
  plt_mean = 300, plt_sd = 80, plt_floor = 120,

  # ---- disease-activity / remission process (BVAS/WG) ----
  remit_intercept = 0.62, remit_rtx = 0.46, remit_relapsing = -0.30,
  remit_pr3 = -0.10, remit_bvas = -0.05,
  remit_day_median = 45.0, remit_day_sigma = 0.55,
  flare_window_start_day = 185L, visit_jitter_sd_day = 3.0,

  # ---- flare process (after remission) ----
  flare_base_haz = 0.045, flare_rtx = -0.20, flare_pr3 = 0.62,
  flare_relapsing = 0.35, flare_pred_protect = -0.020, flare_frailty = 1.0,
  p_flare_severe = 0.45,

  # ---- prednisone taper ----
  pred_start_mgkg = 1.0, pred_taper_end_day = 180L,

  # ---- labs: WBC follows an AR(1) process; CYC myelosuppression is the main arm signal ----
  wbc_ar = 0.5, wbc_cyc_drag = 1.7, wbc_cyc_drag_frailty = 0.7,
  wbc_rtx_drag = 0.6, wbc_rtx_drag_frailty = 0.4, wbc_noise = 0.7,
  hgb_ar = 0.5, hgb_cyc_drag = 0.5, hgb_noise = 0.5,
  plt_ar = 0.5, plt_cyc_drag = 18.0, plt_rtx_drag = 10.0, plt_noise = 22.0,
  anc_frac = 0.6, anc_noise = 0.45,

  # ---- non-lab AE catalog: name -> list(base_haz, frailty_attr, log_rr_cyc, log_rr_rtx, p_severe) ----
  ae_nonlab = list(
    Nausea     = list(base = 0.055, fattr = "f_GI",      lrc = 0.25, lrr = 0.0,  psev = 0.03),
    Vomiting   = list(base = 0.018, fattr = "f_GI",      lrc = 0.50, lrr = 0.0,  psev = 0.05),
    Diarrhoea  = list(base = 0.060, fattr = "f_GI",      lrc = 0.30, lrr = 0.0,  psev = 0.03),
    Alopecia   = list(base = 0.022, fattr = "f_GI",      lrc = 0.65, lrr = -2.0, psev = 0.01),
    Rash       = list(base = 0.030, fattr = "f_GI",      lrc = 0.50, lrr = 0.0,  psev = 0.02),
    Arthralgia = list(base = 0.075, fattr = "f_relapse", lrc = 0.0,  lrr = 0.15, psev = 0.03),
    Fatigue    = list(base = 0.060, fattr = "f_GI",      lrc = 0.0,  lrr = 0.10, psev = 0.04),
    Headache   = list(base = 0.060, fattr = "f_GI",      lrc = 0.0,  lrr = 0.05, psev = 0.02),
    Cough      = list(base = 0.065, fattr = "f_infect",  lrc = 0.0,  lrr = 0.20, psev = 0.03)
  ),

  # ---- infection / serious-disease / infusion / steroid ----
  infect_base_haz = 0.050, infect_frailty = 1.0, infect_rtx = 0.12, infect_cyc = 0.0,
  # serious_disease_rtx: how much the RTX arm raises the serious disease-event hazard. Retuned for
  # R's random-number generator (Python uses 0.65) so the RTX serious-AE rate lands within TOL. A
  # value-only tweak, RTX arm only — no gate or structure change. See README "RNG non-identity".
  infect_pred = 0.004, infect_base_haz_serious_disease = 0.014, serious_disease_rtx = 0.20,
  p_infect_serious = 0.30, infusion_rxn_haz = 0.02,
  steroid_ae_per_mg = 0.0016, steroid_ae_frailty = 0.8,

  # ---- chance an AE of each CTCAE grade gets reported (grade cutoffs are fixed; only these are tunable) ----
  leuko_report   = list(`1` = 0.25, `2` = 0.85, `3` = 0.97, `4` = 1.0),
  anemia_report  = list(`1` = 0.20, `2` = 0.55, `3` = 0.95, `4` = 1.0),
  thrombo_report = list(`1` = 0.20, `2` = 0.70, `3` = 0.95, `4` = 1.0),

  # ---- discontinuation / crossover / death ----
  disc_intercept = -5.2, disc_frailty = 0.5, disc_serious_ae = 0.7, disc_severe_flare = 1.5,
  p_crossover_nonresponse = 0.10, death_base = 0.020, death_serious_ae = 0.03
)

# range checks on the values that must always hold (probabilities in [0,1]; SDs/noise > 0). Checks only, no changes.
RAVE_PARAM_CHECKS <- list(
  p_female = assert_prob, p_usa = assert_prob, p_gpa = assert_prob, p_pr3 = assert_prob,
  p_new_dx = assert_prob, p_flare_severe = assert_prob, p_infect_serious = assert_prob,
  p_crossover_nonresponse = assert_prob,
  age_sd = assert_pos, bvaswg_sd = assert_pos, vdi_sd = assert_pos, wbc_sd = assert_pos,
  plt_sd = assert_pos, remit_day_sigma = assert_pos, visit_jitter_sd_day = assert_pos,
  flare_base_haz = assert_pos, wbc_noise = assert_pos, hgb_noise = assert_pos,
  plt_noise = assert_pos, anc_noise = assert_pos, infect_base_haz = assert_pos,
  infect_base_haz_serious_disease = assert_pos, pred_taper_end_day = assert_posint,
  flare_window_start_day = assert_posint
)

rave_default_params <- function() {
  p <- RAVE_DEFAULT_PARAMS
  validate_params(p, names(RAVE_DEFAULT_PARAMS), RAVE_PARAM_CHECKS)   # error out if a default is out of range
  p
}

# overlay a params/*.json override onto the defaults (for reproducible calibrated runs)
rave_load_params <- function(path) {
  p <- rave_default_params()
  override <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  for (k in names(override)) p[[k]] <- override[[k]]
  validate_params(p, names(RAVE_DEFAULT_PARAMS), RAVE_PARAM_CHECKS)
  p
}
