# RAVE (NCT00104299 / ITN021AI): patient state, latent frailties, and the visit grid.
# Mirrors causal_examples/autoimmune/rave/dag_state.py. ANCA-associated vasculitis; the central
# hidden state is BVAS/WG disease activity (0 = remission). Frailties are drawn once per patient
# and reused at every visit, which is what makes a patient's AEs and labs correlate over time.

# Visit schedule from protocol Appendix 1: screening plus V1..V12. Each entry: key, visit number, study day, label.
RAVE_SCHED <- list(
  list(key = "SCRN", visitnum = 1L,  day = -14L, label = "Screening"),
  list(key = "V1",   visitnum = 2L,  day = 1L,   label = "Baseline"),
  list(key = "V2",   visitnum = 3L,  day = 8L,   label = "Week 1"),
  list(key = "V3",   visitnum = 4L,  day = 15L,  label = "Week 2"),
  list(key = "V4",   visitnum = 5L,  day = 22L,  label = "Week 3"),
  list(key = "V5",   visitnum = 6L,  day = 29L,  label = "Month 1"),
  list(key = "V6",   visitnum = 7L,  day = 60L,  label = "Month 2"),
  list(key = "V7",   visitnum = 8L,  day = 120L, label = "Month 4"),
  list(key = "V8",   visitnum = 9L,  day = 180L, label = "Month 6"),   # PRIMARY endpoint readout
  list(key = "V9",   visitnum = 10L, day = 270L, label = "Month 9"),
  list(key = "V10",  visitnum = 11L, day = 365L, label = "Month 12"),
  list(key = "V11",  visitnum = 12L, day = 455L, label = "Month 15"),
  list(key = "V12",  visitnum = 13L, day = 545L, label = "Month 18")   # end of main study
)

RAVE_PRIMARY_ENDPOINT_DAY <- 180L
RAVE_ADMIN_CENSOR_DAY     <- 545L

VDI_VISITS         <- c("V1", "V8", "V10", "V12")
RTX_INFUSION_VISITS <- c("V1", "V2", "V3", "V4")

# (expit lives in the shared engine, R/skill_root.R)

# visit_info(key) -> list(VISITNUM, VISITDY, VISIT-label)
visit_info <- function(key) {
  for (s in RAVE_SCHED) if (identical(s$key, key)) return(list(VISITNUM = s$visitnum, VISITDY = s$day, VISIT = s$label))
  list()
}

# recorded date for a study day (baseline anchored at day 1)
rave_visit_date <- function(baseline_date, study_day) baseline_date + max(0L, study_day - 1L)

# per-patient random effects, drawn once; SDs match the Python version
draw_frailties <- function() list(
  f_heme    = np_normal(0, 0.7),
  f_infect  = np_normal(0, 0.7),
  f_GI      = np_normal(0, 0.7),
  f_relapse = np_normal(0, 0.8),
  f_steroid = np_normal(0, 0.6),
  f_dropout = np_normal(0, 0.5)
)
