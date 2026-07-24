# STUB trial: the smallest possible TrialSim subclass. It runs the whole base engine (per-patient
# loop, CSV writer, the #182/#183/#184 helpers, the separate jitter stream) with almost no trial
# logic of its own. Not a real trial — it's the skeleton a new trial copies, and the P1 smoke test.

# builds a record as an environment, so it can be updated in place like the real trials' patient/visit/AE records
.rec <- function(...) { e <- new.env(parent = emptyenv()); vals <- list(...); for (k in names(vals)) assign(k, vals[[k]], e); e }

STUB_SCHED <- list(
  list(key = "BL", visitnum = 1L, day = 0L,  label = "Baseline"),
  list(key = "V1", visitnum = 2L, day = 28L, label = "Week 4"),
  list(key = "V2", visitnum = 3L, day = 56L, label = "Week 8")
)

# emitters: DM (one row per patient) and AE (one row per adverse event)
stub_emit_DM <- function(p) tibble::tibble(USUBJID = p$usubjid, ARM = p$arm, DISP = p$disposition)
stub_emit_AE <- function(p) {
  rows <- list()
  for (v in p$trajectory) for (a in v$aes)
    rows[[length(rows) + 1L]] <- tibble::tibble(USUBJID = p$usubjid, AETERM = a$AETERM,
                                                AESER = a$AESER, AEACN = a$AEACN, AEDY = a$AEDY, VISIT = v$key)
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

StubSim <- R6Class("StubSim", inherit = TrialSim, public = list(
  prefix = "STUB", nct = "NCT00000000", sched = STUB_SCHED, admin_censor_day = 60L,
  default_n = 20L, default_seed = 12345L,
  emitters = list(DM = stub_emit_DM, AE = stub_emit_AE),

  make_baseline = function(subj_num) {
    .rec(usubjid = sprintf("STUB-%04d", subj_num),
         arm = if (np_bernoulli(0.5) == 1L) "ACTIVE" else "PLACEBO",
         trajectory = list(),
         discontinuation_reason = NULL, discontinuation_visit_day = NULL, discontinuation_day = NULL)
  },

  simulate_trajectory = function(patient, jit) {
    prev_actual <- -7L
    for (idx in seq_along(self$sched)) {
      s <- self$sched[[idx]]
      next_nom <- if (idx < length(self$sched)) self$sched[[idx + 1L]]$day else self$admin_censor_day
      actual <- self$clamp_actual_day(jit, s$day, prev_actual, next_nom, sd = 2)
      prev_actual <- actual
      aes <- list()
      # some ACTIVE patients get an AE at V1 with onset between visits (exercises #182 and reconcile)
      if (s$key == "V1" && patient$arm == "ACTIVE" && np_random() < 0.4) {
        onset <- self$between(jit, self$sched[[idx - 1L]]$day, s$day)
        aes[[1]] <- .rec(AETERM = "HEADACHE", AESER = "N", AEACN = "DRUG WITHDRAWN", AEDY = onset)
      }
      patient$trajectory[[length(patient$trajectory) + 1L]] <-
        .rec(key = s$key, visit_day = s$day, actual_day = actual, aes = aes)
      # ~15% discontinue for the AE at V1
      if (s$key == "V1" && length(aes) && np_random() < 0.4) {
        patient$discontinuation_reason <- "ADVERSE EVENT"
        patient$discontinuation_visit_day <- s$day
        patient$discontinuation_day <- self$between(jit, s$day, next_nom)
        break
      }
    }
    invisible(patient)
  },

  derive_endpoints = function(patient) {
    patient$disposition <- if (!is.null(patient$discontinuation_reason)) "DISCONTINUED" else "COMPLETED"
    invisible(patient)
  }
))
