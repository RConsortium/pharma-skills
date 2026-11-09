# compute_test.R
# Workflow B compute step: combination test statistics + closed testing at the
# current analysis, via gsDose::combTest (which applies combDunnett internally).
#
# Usage:
#   Rscript compute_test.R config.json gsdose_results.json
#
# The second argument is the results JSON written by compute_boundary.R: the test
# results are attached to the matching endpoint (by name) under its "test" field,
# so the bundle keeps ONE combined results file.
#
# config.json:
# {
#   "endpoint": "OS",
#   "stage": 2,                  # current testing stage k (1-based, testing stages only)
#   "w": [[1,0],[0.899,0.438]],  # stage-weight matrix up to k (row k is used, cols 1..k)
#   "h": [0.293, 0.956],         # cohort weights: pair, or matrix (row k is used)
#   "z1": [[0.8,1,0.7],
#          [0.9,1.2,0.81]],      # cohort-1 cumulative log-rank z, rows = stages 1..k,
#                                #   cols = ALL dose arms vs control
#   "d1": [[40,36,38],
#          [51,42,49]],          # cohort-1 cumulative events per dose-arm-vs-control
#   "z2": 2.35,                  # cohort-2 log-rank z, selected dose, current stage
#   "sid": 2,                    # selected dose (1..K)
#   "ratio": 1,                  # randomization ratio(s) dose:control (Q4b)
#   "zbound": 2.22,              # efficacy bound at current stage (from gsdose_results.json)
#   "z_lower": null              # optional futility bound at current stage
# }
#
# Output: intersections table (doses, DunnettZ1, LogrankZ2, ComboZ, reject),
# the closed-testing decision for the selected dose, and an optional futility check.

suppressPackageStartupMessages({
  library(gsDose)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript compute_test.R config.json gsdose_results.json")
cfg <- fromJSON(args[1], simplifyVector = FALSE)
results_path <- args[2]
if (!file.exists(results_path))
  stop("results file not found: ", results_path,
       " — run compute_boundary.R first (the test results are merged into it)")

num_vec <- function(x) as.numeric(unlist(x))
num_mat <- function(x) {
  if (is.list(x) && length(x) > 0 && is.list(x[[1]])) {
    do.call(rbind, lapply(x, num_vec))
  } else {
    matrix(num_vec(x), nrow = 1)
  }
}

k      <- as.integer(cfg$stage)
w_full <- num_mat(cfg$w)
h_full <- num_mat(cfg$h)          # 1 x 2 if a pair was given
z1     <- num_mat(cfg$z1)
d1     <- num_mat(cfg$d1)
z2     <- as.numeric(cfg$z2)
sid    <- as.integer(cfg$sid)
ratio  <- if (is.null(cfg$ratio)) 1 else num_vec(cfg$ratio)
zbound <- as.numeric(cfg$zbound)

if (nrow(z1) != k || nrow(d1) != k)
  stop("'z1' and 'd1' must have one row per testing stage up to the current stage (", k, ")")
if (ncol(z1) != ncol(d1))
  stop("'z1' and 'd1' must cover the same dose arms")
if (sid < 1 || sid > ncol(z1))
  stop("'sid' must identify one of the ", ncol(z1), " dose arms")
if (k > 1 && any(apply(d1, 2, function(col) any(diff(col) < 0))))
  stop("each dose arm's cohort-1 events in 'd1' must be non-decreasing across stages")

w_k <- if (nrow(w_full) >= k) w_full[k, seq_len(k)] else stop("'w' needs a row for stage ", k)
h_k <- if (nrow(h_full) >= k) h_full[k, ] else h_full[1, ]

res <- combTest(w = w_k, h = h_k, z1 = z1, d1 = d1, z2 = z2,
                sid = sid, zbound = zbound, ratio = ratio)

arm_cols <- seq_len(ncol(z1))
intersections <- lapply(seq_len(nrow(res)), function(i) {
  ind <- as.integer(res[i, arm_cols])
  list(
    hypothesis = rownames(res)[i],
    doses      = which(ind == 1),
    dunnett_z1 = round(res[i, "DunnettZ1"], 4),
    logrank_z2 = round(res[i, "LogrankZ2"], 4),
    combo_z    = round(res[i, "ComboZ"], 4),
    reject     = identical(res[i, "Reject"], "Yes")
  )
})

h_sid_rejected <- all(res[, "Reject"] == "Yes")

futility <- NULL
if (!is.null(cfg$z_lower)) {
  indiv <- which(rowSums(res[, arm_cols, drop = FALSE]) == 1)
  z_indiv <- res[indiv, "ComboZ"]
  futility <- list(
    z_lower          = as.numeric(cfg$z_lower),
    individual_combo_z = round(z_indiv, 4),
    crossed          = z_indiv < as.numeric(cfg$z_lower)
  )
}

out <- list(
  stage          = k,
  sid            = sid,
  zbound         = zbound,
  intersections  = intersections,
  h_sid_rejected = h_sid_rejected,
  decision       = if (h_sid_rejected) {
    paste0("All intersection hypotheses including dose ", sid,
           " are rejected: dose ", sid, " is declared superior to control.")
  } else {
    paste0("Not all intersection hypotheses including dose ", sid,
           " are rejected: no efficacy claim at this analysis; the trial continues.")
  },
  futility       = futility
)

# merge into the combined results JSON under the matching endpoint
res_all <- fromJSON(results_path, simplifyVector = FALSE)
ep_names <- vapply(res_all$endpoints, function(e) as.character(e$name), "")
idx <- match(as.character(cfg$endpoint), ep_names)
if (is.na(idx))
  stop("endpoint '", cfg$endpoint, "' not found in ", results_path,
       " (has: ", paste(ep_names, collapse = ", "), ")")
res_all$endpoints[[idx]]$test <- out
write_json(res_all, results_path, pretty = TRUE, digits = NA, auto_unbox = TRUE)

cat(toJSON(out, pretty = TRUE, digits = NA, auto_unbox = TRUE), "\n")
cat("MERGED into:", results_path, "\n")
