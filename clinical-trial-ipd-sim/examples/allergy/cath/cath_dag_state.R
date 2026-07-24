# CATH (NCT00789880 / ADVN CATH 03-01) — patient state, frailties, and the visit grid.
# Ported from causal_examples/allergy/cath/dag_state.py. Short trial (oral Vitamin D3 4000 IU/day
# vs placebo, 21 days) across 3 diagnosis groups (Psoriasis / AD / Non-AD). Endpoints are
# change-from-baseline biomarker deltas, with no time-to-event.

# Each visit: (key, VISITNUM, nominal study day, label). Day 0 = baseline/randomization.
CATH_SCHED <- list(
  list(key = "SCRN", visitnum = 1L, day = -7L, label = "Screening (Visit 1, Day -7 to -10)"),
  list(key = "BL",   visitnum = 2L, day = 0L,  label = "Baseline (Visit 2, Day 0)"),
  list(key = "D21",  visitnum = 3L, day = 21L, label = "Day 21 (Visit 3, window Day 18-27)")
)
CATH_ADMIN_CENSOR_DAY <- 27L
CATH_PRIMARY_ENDPOINT_DAY <- 21L

CATH_GROUPS <- c("NonAD", "AD", "Psor")
DARK_FITZ <- c("Olive", "ModeratelyBrown", "MarkedlyBlack")   # darker skin -> lower baseline vitamin D (S6)

cath_visit_info <- function(key) {
  for (s in CATH_SCHED) if (identical(s$key, key)) return(list(VISITNUM = s$visitnum, VISITDY = s$day, VISIT = s$label))
  list()
}

# NOTE: CATH anchors the baseline date at study day 0 (RAVE uses day 1 instead).
cath_visit_date <- function(baseline_date, study_day) baseline_date + as.integer(study_day)

# per-patient random effects, shared across all visits (never zeroed — invariant #4)
cath_draw_frailties <- function(P) list(
  f_amp        = np_normal(0, P$sigma_f_amp),
  f_th2        = np_normal(0, P$sigma_f_th2),
  f_vitd_resp  = np_normal(0, P$sigma_f_vitd_resp),
  f_microbiome = np_normal(0, P$sigma_f_microbiome),
  f_ae         = np_normal(0, P$sigma_f_ae),
  f_dropout    = np_normal(0, P$sigma_f_dropout)
)

# pick one key from a named list of probabilities (normalized first)
cath_cat <- function(prob_list) {
  keys <- names(prob_list); p <- as.numeric(unlist(prob_list)); p <- p / sum(p)
  np_choice(keys, prob = p)
}

# find a visit row by key
cath_row <- function(patient, key) { for (r in patient$trajectory) if (identical(r$visit_key, key)) return(r); NULL }
