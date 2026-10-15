#!/usr/bin/env Rscript
# verify_reconstruction.R — Compare digitized KM curves against reconstructed
#   Kaplan-Meier curves from IPD to verify reconstruction quality.
#
# Usage:
#   Rscript verify_reconstruction.R <digitized.json> <ipd_combined.csv> <output_dir>
#
# Outputs (written to output_dir):
#   verification.json  — machine-readable metrics (mae, max_dev, pass per arm)
#
# Pass criteria (per arm):
#   MAE    < 3 percentage points
#   MaxDev < 5 percentage points
#
# How it works:
#   - Reads digitized timepoints and survival % from km_digitized.json
#   - Fits survfit() to the reconstructed IPD for each arm
#   - Evaluates the reconstructed KM step function at every digitized timepoint
#   - Reports mean absolute error and max deviation
#   - Prints PASS/FAIL for each arm and overall

suppressPackageStartupMessages({
  library(jsonlite)
  library(survival)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript verify_reconstruction.R <digitized.json> <ipd_combined.csv> <output_dir>")
}

json_path  <- args[1]
ipd_path   <- args[2]
output_dir <- args[3]
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

MAE_THRESHOLD    <- 3.0   # percentage points
MAXDEV_THRESHOLD <- 5.0   # percentage points

dat    <- fromJSON(json_path)
ipd    <- read.csv(ipd_path, stringsAsFactors = FALSE)
curves <- dat$curves
y_max  <- dat$y_axis$range[2]
scale  <- if (y_max > 1) 100 else 1   # work in % throughout

results  <- list()
all_pass <- TRUE

for (i in seq_along(curves$name)) {
  arm_name <- curves$name[i]
  pts      <- curves$points[[i]]
  dig_time <- pts$time
  dig_surv <- pts$survival   # in % scale

  arm_ipd <- ipd[ipd$arm == arm_name, ]
  if (nrow(arm_ipd) == 0) {
    cat(sprintf("WARNING: No IPD found for arm '%s' — skipping\n", arm_name))
    next
  }

  fit <- survfit(Surv(time, event) ~ 1, data = arm_ipd)

  # Evaluate reconstructed KM at each digitized timepoint via step function
  rec_fn   <- stepfun(fit$time, c(1, fit$surv))
  rec_surv <- rec_fn(dig_time) * scale

  abs_diff <- abs(dig_surv - rec_surv)
  mae      <- mean(abs_diff)
  maxdev   <- max(abs_diff)
  pass     <- mae < MAE_THRESHOLD & maxdev < MAXDEV_THRESHOLD

  if (!pass) all_pass <- FALSE

  results[[arm_name]] <- list(
    mae    = round(mae,    2),
    maxdev = round(maxdev, 2),
    pass   = pass,
    n_pts  = length(dig_time)
  )

  status <- if (pass) "PASS" else "FAIL"
  cat(sprintf("[%s] %s\n", status, arm_name))
  cat(sprintf("       MAE = %.2f pp  |  MaxDev = %.2f pp  |  n = %d digitized points\n",
              mae, maxdev, length(dig_time)))
}

cat(sprintf("\nThresholds: MAE < %.0f pp, MaxDev < %.0f pp\n",
            MAE_THRESHOLD, MAXDEV_THRESHOLD))
cat(sprintf("Overall: %s\n", if (all_pass) "PASS" else "FAIL"))

if (!all_pass) {
  cat("\nDiagnostic steps when FAIL:\n")
  cat("  1. Inspect the debug overlay image — are tracked dots on the correct curve?\n")
  cat("  2. Add more calibration points (aim for 5+ per arm across the full time range)\n")
  cat("  3. Verify plot_region pixels land exactly on the axis lines (use wizard or dark-line scan)\n")
  cat("  4. Check number_at_risk keys match curve names exactly\n")
}

out <- list(
  pass       = all_pass,
  thresholds = list(mae_pp = MAE_THRESHOLD, maxdev_pp = MAXDEV_THRESHOLD),
  arms       = results
)
json_out <- file.path(output_dir, "verification.json")
write_json(out, json_out, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\nMetrics saved: %s\n", json_out))

# Exit with non-zero code on failure so callers can detect it
if (!all_pass) quit(status = 1)
