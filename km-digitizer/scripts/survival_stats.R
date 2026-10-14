#!/usr/bin/env Rscript
# survival_stats.R — Compute median and survival rates per arm
#
# Usage:
#   Rscript survival_stats.R <ipd_combined.csv> <times_comma_separated>
#
# Output: lines of the form:
#   <arm_name> MEDIAN <value>
#   <arm_name> SURV <time> <value>

suppressPackageStartupMessages(library(survival))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript survival_stats.R <ipd.csv> <times>")
}

ipd_path <- args[1]
times <- as.numeric(strsplit(args[2], ",")[[1]])

ipd <- read.csv(ipd_path, stringsAsFactors = FALSE)
arms <- unique(ipd$arm)

for (arm_name in arms) {
  ad <- ipd[ipd$arm == arm_name, ]
  fit <- survfit(Surv(time, event) ~ 1, data = ad)
  sf <- summary(fit, times = times)
  med <- unname(quantile(fit, probs = 0.5)$quantile)
  cat(arm_name, "MEDIAN", sprintf("%.1f", med), "\n")
  for (j in seq_along(times)) {
    cat(arm_name, "SURV", times[j], sprintf("%.1f", sf$surv[j] * 100), "\n")
  }
}
