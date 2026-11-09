# compute_w_weights.R
# Derive the cohort-1 stage weights (w) for gsDose::combTest from expected events,
# following gsDose vignettes/Introduction.Rmd.
#
# Usage:
#   Rscript compute_w_weights.R config.json [out.json]
#
# config.json fields:
#   plan_events     : planned events at each testing analysis, counting only the
#                     selected dose arm + control (both cohorts), strictly
#                     increasing, e.g. [260, 416, 520]
#   enroll_total    : {"duration": [...], "rate": [...]}  piecewise enrollment,
#                     months and patients/month, selected dose + control arms only
#   enroll_cohort1  : {"duration": [...], "rate": [...]}  the leading portion of
#                     the ramp enrolled before dose selection (cohort 1)
#   median_control  : control-arm median survival in months
#   hr              : hazard ratio, treatment vs control
#   dropout_rate    : annual dropout hazard rate (0 if none); default 0
#   ratio           : randomization ratio treatment:control; default 1
#
# Output (stdout and optional out.json):
#   expected_time     : calendar time each analysis is expected to occur
#   d_cohort1         : expected cohort-1 events at each analysis
#   d_cohort2         : expected cohort-2 events at each analysis
#                       (plan_events - d_cohort1; same population as plan_events)
#   w                 : weight matrix, rows = analyses, cols = increments;
#                       row k is c(sqrt(d1/dk), sqrt((d2-d1)/dk), ..., 0, ...)
#                       and row 1 is c(1, 0, ..., 0)

suppressPackageStartupMessages({
  library(gsDesign2)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript compute_w_weights.R config.json [out.json]")
cfg <- fromJSON(args[1])

plan_events <- cfg$plan_events
if (is.unsorted(plan_events, strictly = TRUE))
  stop("plan_events must be strictly increasing across analyses")
dropout <- if (is.null(cfg$dropout_rate)) 0 else cfg$dropout_rate
ratio   <- if (is.null(cfg$ratio)) 1 else cfg$ratio

enroll <- define_enroll_rate(
  duration = cfg$enroll_total$duration,
  rate     = cfg$enroll_total$rate
)
enroll_n1 <- define_enroll_rate(
  duration = cfg$enroll_cohort1$duration,
  rate     = cfg$enroll_cohort1$rate
)
fail_rate <- define_fail_rate(
  duration     = 1000,
  fail_rate    = log(2) / cfg$median_control,
  hr           = cfg$hr,
  dropout_rate = dropout
)

L <- length(plan_events)
exp_time <- rep(NA_real_, L)
d_n1     <- rep(NA_real_, L)

for (j in seq_len(L)) {
  t_j <- expected_time(
    enroll_rate = enroll, fail_rate = fail_rate,
    ratio = ratio, target_event = plan_events[j], interval = c(0.01, 1000)
  )
  exp_time[j] <- t_j$time
  d_n1[j] <- expected_event(
    enroll_rate = enroll_n1, fail_rate = fail_rate,
    total_duration = t_j$time, simple = TRUE
  )
}

if (is.unsorted(d_n1, strictly = TRUE))
  stop("expected cohort-1 events are not increasing across analyses; check inputs")

# w matrix: row k = sqrt(incremental cohort-1 event fractions up to analysis k)
w <- matrix(0, nrow = L, ncol = L)
incr <- diff(c(0, d_n1))
for (k in seq_len(L)) {
  w[k, seq_len(k)] <- sqrt(incr[seq_len(k)] / d_n1[k])
}

# each row's squared weights must sum to 1
stopifnot(all(abs(rowSums(w^2) - 1) < 1e-8))

d_n2 <- plan_events - d_n1
if (any(d_n2 < 0))
  stop("expected cohort-1 events exceed plan_events; check that plan_events and the enrollment ramps cover the same population (selected dose + control)")

out <- list(
  expected_time = round(exp_time, 2),
  d_cohort1     = round(d_n1, 2),
  d_cohort2     = round(d_n2, 2),
  w             = round(w, 6)
)
cat(toJSON(out, pretty = TRUE, digits = NA), "\n")
if (length(args) >= 2) write_json(out, args[2], pretty = TRUE, digits = NA)
