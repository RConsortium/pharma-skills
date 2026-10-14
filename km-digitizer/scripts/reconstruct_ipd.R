#!/usr/bin/env Rscript
# reconstruct_ipd.R — Reconstruct individual patient-level TTE data from
#   digitized KM coordinates using the IPDfromKM package.
#
# Usage:
#   Rscript reconstruct_ipd.R <digitized.json> <output_dir>
#
# Inputs:
#   digitized.json  — output from digitize_km.py, containing:
#     - curves[].name, curves[].points (time, survival)
#     - number_at_risk.times, number_at_risk.counts (per curve name)
#
# Outputs (written to output_dir):
#   ipd_<arm_name>.csv  — per-arm IPD with columns: time, event, arm
#   ipd_combined.csv    — all arms combined

suppressPackageStartupMessages({
  library(jsonlite)
  library(IPDfromKM)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript reconstruct_ipd.R <digitized.json> <output_dir>")
}

json_path <- args[1]
output_dir <- args[2]
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# --- Read digitized JSON ---
dat <- fromJSON(json_path)
curves <- dat$curves
n_curves <- nrow(curves) %||% length(curves$name)

# Extract number-at-risk
nar <- dat$number_at_risk
if (is.null(nar)) {
  stop("number_at_risk not found in JSON. Required for IPD reconstruction.")
}
trisk <- nar$times

# y-axis scale: if max survival > 1 (percentage), divide by 100
y_max <- dat$y_axis$range[2]
scale <- if (y_max > 1) 100 else 1

cat(sprintf("Input: %s\n", json_path))
cat(sprintf("Curves: %d, Number-at-risk timepoints: %d\n", n_curves, length(trisk)))

# --- Reconstruct IPD for each curve ---
all_ipd <- data.frame()

for (i in seq_len(n_curves)) {
  arm_name <- curves$name[i]
  pts <- curves$points[[i]]
  time_vec <- pts$time
  surv_vec <- pts$survival / scale  # normalize to 0-1

  # Number at risk for this arm
  nrisk <- nar$counts[[arm_name]]
  if (is.null(nrisk)) {
    # Try matching by position
    count_names <- names(nar$counts)
    if (i <= length(count_names)) {
      nrisk <- nar$counts[[count_names[i]]]
      cat(sprintf("  Matched '%s' to nrisk key '%s'\n", arm_name, count_names[i]))
    }
  }
  if (is.null(nrisk)) {
    stop(sprintf("No number_at_risk data found for '%s'", arm_name))
  }

  totalpts <- nrisk[1]
  cat(sprintf("\n--- %s (N=%d) ---\n", arm_name, totalpts))

  # Prepare data frame for IPDfromKM
  coord_df <- data.frame(time = time_vec, surv = surv_vec)

  # preprocess: trisk and nrisk must have same length
  prep <- preprocess(
    dat = coord_df,
    trisk = trisk,
    nrisk = nrisk,
    totalpts = totalpts,
    maxy = 1
  )

  # Extract IPD
  ipd_result <- getIPD(prep, armID = 0, tot.events = NULL)
  ipd_df <- ipd_result$IPD[, 1:2]
  colnames(ipd_df) <- c("time", "event")
  ipd_df$arm <- arm_name

  # Redistribute tail-censored patients across NaR intervals beyond last event.
  # getIPD piles all censoring at the last event time; use NaR to spread them.
  x_max    <- dat$x_axis$range[2]
  max_time <- max(ipd_df$time)
  if (x_max > max_time + 0.01) {
    tail_mask <- trisk > max_time & trisk <= x_max
    t_tail    <- trisk[tail_mask]
    n_tail    <- nrisk[tail_mask]
    if (length(t_tail) > 0 && n_tail[1] > 0) {
      piled       <- which(ipd_df$event == 0 & abs(ipd_df$time - max_time) < 0.01)
      n_to_spread <- min(n_tail[1], length(piled))
      spread_idx <- tail(piled, n_to_spread)
      set.seed(42)
      new_times  <- numeric(n_to_spread)
      pos <- 1
      for (j in seq_len(length(t_tail) - 1)) {
        n_here <- n_tail[j] - n_tail[j + 1]
        if (n_here > 0 && pos <= n_to_spread) {
          take <- min(n_here, n_to_spread - pos + 1)
          new_times[pos:(pos + take - 1)] <- runif(take, t_tail[j], t_tail[j + 1])
          pos <- pos + take
        }
      }
      ipd_df$time[spread_idx] <- new_times
      cat(sprintf("  Tail censoring spread: %d patients -> [%.1f, %.1f]\n",
                  n_to_spread, max_time, x_max))
    }
  }

  # Enforce exact N from number-at-risk table
  if (nrow(ipd_df) > totalpts) {
    excess <- nrow(ipd_df) - totalpts
    # Remove excess censored observations (event==0) from the tail
    censored_idx <- which(ipd_df$event == 0)
    if (length(censored_idx) >= excess) {
      remove_idx <- tail(censored_idx, excess)
    } else {
      remove_idx <- tail(seq_len(nrow(ipd_df)), excess)
    }
    ipd_df <- ipd_df[-remove_idx, , drop = FALSE]
    cat(sprintf("  Trimmed %d excess patients to match N=%d\n", excess, totalpts))
  }

  cat(sprintf("  Reconstructed: %d patients, %d events\n",
              nrow(ipd_df), sum(ipd_df$event)))

  # Save per-arm CSV
  arm_file <- gsub("[^A-Za-z0-9]", "_", tolower(arm_name))
  arm_path <- file.path(output_dir, paste0("ipd_", arm_file, ".csv"))
  write.csv(ipd_df, arm_path, row.names = FALSE)
  cat(sprintf("  Saved: %s\n", arm_path))

  all_ipd <- rbind(all_ipd, ipd_df)
}

# Save combined CSV
combined_path <- file.path(output_dir, "ipd_combined.csv")
write.csv(all_ipd, combined_path, row.names = FALSE)
cat(sprintf("\nCombined IPD saved: %s (%d total patients)\n",
            combined_path, nrow(all_ipd)))
