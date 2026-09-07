#!/usr/bin/env Rscript
# Executed witnesses for BR-001 (tie method), BR-002 (rounding stage) and
# BR-003 (display precision).
#
# Usage:
#   Rscript probe-tie-behavior.R                       # answer-key probe
#   Rscript probe-tie-behavior.R --digits 2            # probe at 2 decimals
#   Rscript probe-tie-behavior.R --digits 1 --values -2.25,2.25,0.05
#
# Why it is parameterised: the rules apply at the precision each reported
# statistic actually uses, so a fixed vector at zero decimals cannot witness a
# site that displays two decimals. Run the default once for the environment
# record, then re-run with --digits for each in-scope precision.
#
# Why nothing aborts early: this script is the evidence, so a surprising
# result must still be printed. Every check is recorded and the run exits
# nonzero at the end if a documented invariant did not hold -- you get the
# full witness log either way.
#
# base::round() appears below only to demonstrate the failure mode. The
# policy-correct column is always computed with half-away arithmetic.

PROBE_VERSION <- "2.0"

## ---- args -------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
getopt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[i + 1L]
}
digits <- as.integer(getopt("--digits", "0"))
values_arg <- getopt("--values", NA_character_)
if (is.na(digits)) stop("--digits must be an integer")

## ---- policy reference --------------------------------------------------------
## Half away from zero, dependency-free, so BR-002 and BR-003 witnesses are
## always producible even on a machine with no rounding package installed.
## This is a reference for generating evidence. The fix a report recommends is
## still a versioned package helper -- see references/br-001-tie-method.md.
half_away <- function(x, digits = 0) {
  scale <- 10^digits
  sign(x) * trunc(abs(x) * scale + 0.5) / scale
}
fixed <- function(x, digits) formatC(x, format = "f", digits = digits)

checks <- list()
record <- function(id, ok, detail) {
  checks[[length(checks) + 1L]] <<- list(id = id, ok = ok, detail = detail)
  cat(sprintf("%-28s %-4s %s\n", id, if (ok) "OK" else "DIFF", detail))
}

## ---- environment --------------------------------------------------------------
cat("== environment ==\n")
cat("probe_version:", PROBE_VERSION, "\n")
cat("r_version:", R.version.string, "\n")
cat("platform:", R.version$platform, "\n")
cat("probe_digits:", digits, "\n")
for (p in c("cards", "tidytlg", "janitor", "scrutiny")) {
  v <- if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else "NOT INSTALLED"
  cat(sprintf("pkg %-9s %s\n", p, v))
}

## ---- BR-001: exact ties at the requested precision ---------------------------
## An exact tie is one the binary representation stores exactly: 2.5 at zero
## decimals, 1.25 at one, 0.125 at two. Only here is the tie mode the sole
## cause, so only here is the outcome predictable from the source.
cat("\n== BR-001 tie mode: exact ties at", digits, "decimals ==\n")
## A decimal tie is only stored exactly when it is an odd multiple of
## 1/2^(digits+1): 0.5 at 0 decimals, 0.25/0.75/1.25 at 1, 0.125/0.375 at 2.
## Generating anything else here and calling it an "exact tie" would be the
## same overreach this skill exists to catch, so the vector is built from
## that identity and then verified.
unit <- 1 / 2^(digits + 1)
exact <- if (!is.na(values_arg)) {
  as.numeric(strsplit(values_arg, ",")[[1]])
} else {
  sort(as.vector(c(-1, 1) %o% (c(1, 3, 5) * unit)))
}
exactly_stored <- all(abs(exact * 2^(digits + 1) -
  round(exact * 2^(digits + 1))) < .Machine$double.eps)
cat("inputs_exactly_representable:", exactly_stored, "\n")
base_r <- base::round(exact, digits)
policy <- half_away(exact, digits)
cat(sprintf("%12s %12s %12s\n", "input", "base::round", "policy"))
for (i in seq_along(exact)) {
  cat(sprintf("%12s %12s %12s\n", fixed(exact[i], digits + 2),
    fixed(base_r[i], digits), fixed(policy[i], digits)))
}
n_diff <- sum(fixed(base_r, digits) != fixed(policy, digits))
record("br001_base_vs_policy", n_diff > 0,
  sprintf("base::round differs from policy on %d of %d exact ties", n_diff, length(exact)))

## ---- BR-001: the two causes, kept apart ---------------------------------------
## Tie mode and binary representation are separate causes and a report must
## name them separately. formatC() and round() disagree with each other here,
## which is only explicable once both causes are on the table.
cat("\n== BR-001 two causes: stored-inexact ties (pinned answer key, 1dp) ==\n")
## This vector is fixed on purpose. It is the reproducibility anchor: the same
## ten inputs at one decimal, so two runs in the same environment can be
## compared line for line regardless of --digits.
mixed <- c(-76.05, -3.05, -2.05, -1.05, -0.05, 0.05, 1.05, 2.05, 3.05, 76.05)
d <- 1L
f_out <- formatC(mixed, format = "f", digits = d)
r_out <- fixed(base::round(mixed, d), d)
a_out <- fixed(half_away(mixed, d), d)
cat(sprintf("%12s %10s %10s %10s\n", "input", "formatC", "round", "policy"))
for (i in seq_along(mixed)) {
  cat(sprintf("%12s %10s %10s %10s\n", format(mixed[i], nsmall = d + 1),
    f_out[i], r_out[i], a_out[i]))
}
cat(sprintf("formatC disagreements: %d of %d\n", sum(f_out != a_out), length(mixed)))
cat(sprintf("round disagreements:   %d of %d\n", sum(r_out != a_out), length(mixed)))
cat("cause 1 (tie mode): base::round is half-to-even at a true tie.\n")
cat("cause 2 (binary representation): most decimal ties are not stored\n")
cat("  exactly, so the result follows the stored value, not the printed one.\n")
cat("Report these as two causes. 'formatC uses banker's rounding' is wrong.\n")
if (digits == 0L) {
  cat("At 0 decimals every x.5 tie is stored exactly, so cause 1 acts alone\n")
  cat("  there; cause 2 only appears once a site displays decimals.\n")
} else if (digits != 1L) {
  cat(sprintf("\n-- stored-inexact ties at the requested %d decimals --\n", digits))
  inx <- c(-76, -3, -2, -1, 0, 1, 2, 3, 76) + 5 / 10^(digits + 1)
  fi <- formatC(inx, format = "f", digits = digits)
  ri <- fixed(base::round(inx, digits), digits)
  ai <- fixed(half_away(inx, digits), digits)
  cat(sprintf("%14s %10s %10s %10s\n", "input", "formatC", "round", "policy"))
  for (i in seq_along(inx)) {
    cat(sprintf("%14s %10s %10s %10s\n", formatC(inx[i], format = "f",
      digits = digits + 2), fi[i], ri[i], ai[i]))
  }
  cat(sprintf("formatC disagreements: %d of %d | round disagreements: %d of %d\n",
    sum(fi != ai), length(inx), sum(ri != ai), length(inx)))
}

## ---- BR-001: negative zero ------------------------------------------------------
cat("\n== BR-001 negative zero ==\n")
## A magnitude strictly inside the half-ulp: it must display as zero, and the
## question is only whether the sign survives.
small <- -0.4 / 10^digits
nz_round <- fixed(base::round(small, digits), digits)
nz_direct <- formatC(small, format = "f", digits = digits)
record("br001_negzero", grepl("^-0[.]?0*$", nz_direct) || grepl("^-0[.]?0*$", nz_round),
  sprintf("formatC(%s) -> '%s'; round then format -> '%s' (policy: never a signed zero)",
    small, nz_direct, nz_round))

## ---- BR-002: stage ---------------------------------------------------------------
cat("\n== BR-002 rounding stage ==\n")
x <- c(1.25, 1.25, 1.75)
once <- fixed(half_away(mean(x), 1), 1)
early <- fixed(half_away(mean(half_away(x, 1)), 1), 1)
record("br002_mean_stage", once != early,
  sprintf("x = c(1.25,1.25,1.75) at 1dp: round-once '%s' vs early-rounded '%s'", once, early))

thr <- 2.5
record("br002_threshold", (base::round(thr, 0) >= thr) != (thr >= thr),
  sprintf("threshold >= %s: early-rounded keeps %s, unrounded keeps %s",
    thr, base::round(thr, 0) >= thr, thr >= thr))

## ---- BR-003: display -------------------------------------------------------------
cat("\n== BR-003 display precision ==\n")
record("br003_fixed_width", identical(formatC(76, format = "f", digits = 2), "76.00"),
  sprintf("formatC(76, format='f', digits=2) -> '%s' (spec: '76.00')",
    formatC(76, format = "f", digits = 2)))
record("br003_sprintf", identical(sprintf("%.2f", 76), "76.00"),
  sprintf("sprintf('%%.2f', 76) -> '%s' (spec: '76.00')", sprintf("%.2f", 76)))
record("br003_numeric_only", identical(as.character(76.00), "76"),
  sprintf("as.character(76.00) -> '%s' -- a numeric-only helper is not a trailing-zero fix",
    as.character(76.00)))

## ---- installed helpers ------------------------------------------------------------
## Cross-check the built-in reference against a versioned package when one is
## present. A MISMATCH is information, not a failure: pin the package the rule
## owner selected and report what it does.
cat("\n== installed half-away helpers ==\n")
check_helper <- function(pkg, fun) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("helper %-9s SKIPPED (not installed)\n", pkg)); return(invisible())
  }
  got <- tryCatch(do.call(getFromNamespace(fun, pkg), list(exact, digits)),
    error = function(e) paste("ERROR:", conditionMessage(e)))
  ok <- is.numeric(got) && identical(fixed(got, digits), fixed(policy, digits))
  cat(sprintf("helper %-9s v%-8s %s [%s vs built-in reference]\n", pkg,
    as.character(packageVersion(pkg)),
    paste(if (is.numeric(got)) fixed(got, digits) else got, collapse = ","),
    if (ok) "MATCH" else "MISMATCH"))
}
check_helper("cards", "round5")
check_helper("tidytlg", "roundSAS")
check_helper("janitor", "round_half_up")

## ---- summary -------------------------------------------------------------------
cat("\n== summary ==\n")
bad <- Filter(function(c) !c$ok, checks)
cat(sprintf("checks_run: %d  invariants_held: %d  unexpected: %d\n",
  length(checks), length(checks) - length(bad), length(bad)))
if (length(bad)) {
  for (c in bad) cat(sprintf("UNEXPECTED %s: %s\n", c$id, c$detail))
  cat("An unexpected result is a stop condition: this environment does not\n")
  cat("behave as the rule references describe. Record it and escalate.\n")
  quit(status = 1L)
}
cat("probe_done: every documented invariant held in this environment\n")
