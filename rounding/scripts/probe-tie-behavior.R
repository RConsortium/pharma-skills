#!/usr/bin/env Rscript
# Fixed tie/stage/display witnesses for the rounding skill.
# Usage: Rscript probe-tie-behavior.R
# Base-R checks always run with stopifnot(); helper checks run when the
# package is installed and report MATCH/MISMATCH/SKIPPED without failing.
# Rule: banker's rounding (base::round, round-to-even) appears below ONLY
# to demonstrate the failure mode -- a policy-correct value is always
# computed with a half-away helper, never with base::round.

cat("r_version:", R.version.string, "\n")
for (p in c("cards", "tidytlg", "janitor", "scrutiny")) {
  v <- if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else "NOT INSTALLED"
  cat(sprintf("pkg %s: %s\n", p, v))
}

## BR-001: exact binary ties -- deterministic, asserted
base0 <- base::round(c(-2.5, -1.5, 1.5, 2.5), 0)
cat("base_ties_0dp:", paste(base0, collapse = ","), "(policy: -3,-2,2,3)\n")
stopifnot(identical(base0, c(-2, -2, 2, 2)))

base1 <- base::round(c(-1.25, 1.25), 1)
cat("base_ties_1dp:", paste(base1, collapse = ","), "(policy: -1.3,1.3)\n")
stopifnot(identical(base1, c(-1.2, 1.2)))

base2 <- base::round(c(-0.125, 0.125), 2)
cat("base_ties_2dp:", paste(base2, collapse = ","), "(policy: -0.13,0.13)\n")
stopifnot(identical(base2, c(-0.12, 0.12)))

## BR-001: inexact ties are platform-shaped -- printed, never asserted
inexact <- base::round(c(-2.05, 2.05, 1.05, 76.05), 1)
cat("inexact_1dp:", paste(format(inexact, nsmall = 1), collapse = ","),
  "(binary representation, not policy)\n")

## BR-001: helpers map ties away from zero -- reported, never fatal
check_helper <- function(pkg, fun, vec, digits, expected) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("helper %s: SKIPPED (not installed)\n", pkg))
    return(invisible(NULL))
  }
  got <- tryCatch(do.call(getFromNamespace(fun, pkg), list(vec, digits)),
    error = function(e) paste("ERROR:", conditionMessage(e)))
  status <- if (identical(got, expected)) "MATCH" else "MISMATCH"
  cat(sprintf("helper %s::%s: %s [%s] (policy: %s)\n", pkg, fun,
    paste(got, collapse = ","), status, paste(expected, collapse = ",")))
}
check_helper("cards", "round5", c(-2.5, -1.5, 1.5, 2.5), 0, c(-3, -2, 2, 3))
check_helper("tidytlg", "roundSAS", c(-2.5, -1.5, 1.5, 2.5), 0, c(-3, -2, 2, 3))
check_helper("janitor", "round_half_up", c(-2.5, -1.5, 1.5, 2.5), 0, c(-3, -2, 2, 3))

## BR-001: negative zero -- asserted
neg0 <- formatC(-0.5, digits = 0, format = "f")
cat("negzero_0dp:", neg0, "(policy: never -0)\n")
stopifnot(identical(neg0, "-0"))

## BR-002: early rounding flips a threshold decision.
## base::round below models the defective early path only -- never the fix.
thr <- 2.5
early_decides <- base::round(2.5, 0) >= thr
true_decides <- 2.5 >= thr
cat(sprintf("stage_threshold: early=%s true=%s\n", early_decides, true_decides))
stopifnot(identical(early_decides, FALSE), identical(true_decides, TRUE))

## BR-002: early rounding shifts a displayed mean.
## x <- c(1.25, 1.25, 1.75) at one decimal: policy (round once) gives 1.4.
## The compliant path uses a half-away helper -- never banker's rounding.
half_away <- function(x, digits) {
  tryCatch({
    if (requireNamespace("janitor", quietly = TRUE)) return(janitor::round_half_up(x, digits))
    if (requireNamespace("cards", quietly = TRUE)) return(cards::round5(x, digits))
    if (requireNamespace("tidytlg", quietly = TRUE)) return(tidytlg::roundSAS(x, digits))
    NULL
  }, error = function(e) NULL)
}
once <- half_away(mean(c(1.25, 1.25, 1.75)), 1)
if (is.null(once)) {
  cat("stage_round_once_1dp: SKIPPED (needs a half-away helper; policy: 1.4)\n")
} else {
  cat("stage_round_once_1dp:", once, "\n")
  stopifnot(identical(once, 1.4))
  early <- half_away(mean(half_away(c(1.25, 1.25, 1.75), 1)), 1)
  cat("stage_early_halfaway_1dp:", early, "(policy: 1.4)\n")
}

## BR-003: fixed character output -- asserted
s1 <- formatC(76, format = "f", digits = 2)
s2 <- sprintf("%.2f", 76)
cat("display_fixed:", s1, "/", s2, "\n")
stopifnot(identical(s1, "76.00"), identical(s2, "76.00"))
bad <- as.character(76.00)
cat("display_numeric_only:", bad, "(fails trailing zeros)\n")
stopifnot(identical(bad, "76"))

cat("probe_done: all asserted checks passed\n")
