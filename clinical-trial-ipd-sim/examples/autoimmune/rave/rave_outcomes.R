# Y: derive the RAVE endpoints from the simulated trajectory. Mirrors rave_outcomes.py.
# PRIMARY endpoint = complete remission at 6 months: BVAS/WG == 0 AND prednisone == 0 on day 180,
# read straight off the trajectory rather than sampled. (reconcile_ae_ds runs in the engine's
# simulate_one, not here.)

rave_derive_endpoints <- function(sim, patient) {
  P <- sim$params; traj <- patient$trajectory

  # PRIMARY: complete remission at 6 months (read at day 180 / V8)
  v8 <- NULL
  for (r in traj) if (r$visit_day == RAVE_PRIMARY_ENDPOINT_DAY) { v8 <- r; break }
  patient$cr_6mo <- if (!is.null(v8)) as.integer(v8$bvaswg == 0.0 && v8$prednisone_dose == 0.0) else 0L

  # time to complete remission (first visit with BVAS/WG = 0 and off glucocorticoids)
  for (r in traj) if (r$bvaswg == 0.0 && r$prednisone_dose == 0.0) { patient$time_to_cr_day <- r$visit_day; break }

  # how long remission lasted, up to the first flare (else censored at last visit / month 18)
  if (!is.null(patient$flare_day) && !is.null(patient$remission_day)) {
    patient$remission_duration_day <- max(0, patient$flare_day - patient$remission_day)
  } else if (!is.null(patient$remission_day)) {
    last <- if (length(traj)) traj[[length(traj)]]$visit_day else patient$remission_day
    patient$remission_duration_day <- max(0, min(RAVE_ADMIN_CENSOR_DAY, last) - patient$remission_day)
  }

  # death (rare; ~2 per arm over 18 mo)
  p_death <- P$death_base + P$death_serious_ae * (if (patient$serious_ae) 1 else 0)
  if (np_random() < p_death) {
    lo <- patient$discontinuation_visit_day %||% 60
    patient$death_day <- np_integers(min(lo, 500), RAVE_ADMIN_CENSOR_DAY + 1L)
  }

  # disposition
  if (!is.null(patient$death_day)) {
    patient$disposition <- "DEATH"
    patient$discontinuation_reason <- patient$discontinuation_reason %||% "DEATH"
    patient$last_contact_day <- patient$death_day
  } else if (!is.null(patient$discontinuation_day)) {
    patient$disposition <- "DISCONTINUED"
    patient$last_contact_day <- patient$discontinuation_day
  } else {
    patient$disposition <- "COMPLETED"
    patient$last_contact_day <- if (length(traj)) traj[[length(traj)]]$visit_day else RAVE_ADMIN_CENSOR_DAY
  }
  invisible(patient)
}
