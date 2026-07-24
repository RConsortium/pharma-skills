# calibrate.R — the params-only, fail-closed calibration loop (the crf-calibration-loop sub-skill's
# engine; see calibration.md). It tunes ONLY structural-equation PARAMETERS, never structure, and it
# re-runs the trial's DAG gates on every candidate — a gate-breaking or error-raising update is
# reverted, never shipped. Marginals + gates are read from the EMITTED CSVs, matching the gate discipline.
#
# Two entry points:
#   calibration_report(sim, ...)  — simulate once, measure, compare vs targets (the common Step-6 path
#                                    for a trial whose params.json is already calibrated: verify + report).
#   calibrate(sim, targets, knob_map, ...) — the iterative loop for a NEW trial: adjusts one knob at a
#                                    time toward the worst-off marginal, damped (step halves on a move
#                                    that doesn't help), fail-closed, <= max_iter iterations.

# run the sim to a throwaway dir with gates fail-closed; return the measured marginals (named numeric).
.calib_measure <- function(sim, n = NULL, seed = NULL) {
  work <- file.path(tempdir(), paste0("calib_", as.integer(runif(1, 1, 1e9))))
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  sim$run(n_patients = n %||% sim$fixed_n %||% sim$default_n, seed = seed,
          out_dir = work, verify = TRUE, render_html = FALSE, manifest = FALSE)   # fail-closed on gates
  sim$measure_marginals(work)
}

# Simulate + measure + (optionally) compare for an already-calibrated trial. compare_fn(marg) -> a
# comparison object (e.g. the trial's own cath_compare(marg, targets)); if NULL, just returns marginals.
calibration_report <- function(sim, n = NULL, seed = NULL, compare_fn = NULL) {
  marg <- .calib_measure(sim, n = n, seed = seed)
  list(marginals = marg, comparison = if (is.null(compare_fn)) NULL else compare_fn(marg))
}

# max normalized absolute error across the target metrics.
.calib_err <- function(marg, targets, scales) {
  max(vapply(names(targets), function(k) abs((as.numeric(marg[[k]]) - targets[[k]]) / scales[[k]]), numeric(1)))
}

# Iterative calibration. targets: named numeric. knob_map: named list keyed by TARGET metric ->
# list(knob=<param name>, dir=<sign of d(metric)/d(knob)>, step=<initial step>, min=, max=). scales:
# per-metric normalizer (default 1). Returns the tuned params + history; sim$params is left tuned.
calibrate <- function(sim, targets, knob_map, scales = NULL, max_iter = 8L, tol = 0.05,
                      n = NULL, seed = NULL) {
  if (is.null(scales)) scales <- setNames(as.list(rep(1, length(targets))), names(targets))
  best_m <- .calib_measure(sim, n = n, seed = seed)
  best_err <- .calib_err(best_m, targets, scales)
  history <- list(list(iter = 0L, err = best_err, params = sim$params))
  for (it in seq_len(max_iter)) {
    if (best_err <= tol) break
    errs <- vapply(names(targets), function(k) abs((as.numeric(best_m[[k]]) - targets[[k]]) / scales[[k]]), numeric(1))
    worst <- names(targets)[which.max(errs)]
    km <- knob_map[[worst]]
    if (is.null(km)) break                                  # no knob for the worst metric -> stop
    gap <- targets[[worst]] - as.numeric(best_m[[worst]])   # + means metric too low
    step <- km$step * sign(gap) * km$dir
    saved <- sim$params[[km$knob]]
    sim$params[[km$knob]] <- clip(saved + step, km$min, km$max)
    cand <- tryCatch(.calib_measure(sim, n = n, seed = seed), error = function(e) NULL)  # gates fail-closed
    cand_err <- if (is.null(cand)) Inf else .calib_err(cand, targets, scales)
    if (cand_err < best_err) {                              # accept
      best_m <- cand; best_err <- cand_err
    } else {                                                # revert + damp
      sim$params[[km$knob]] <- saved; km$step <- km$step / 2; knob_map[[worst]] <- km
    }
    history[[length(history) + 1L]] <- list(iter = it, worst = worst, knob = km$knob,
                                            value = sim$params[[km$knob]], err = best_err)
  }
  status <- if (best_err <= tol) "SUCCESS" else "STALLED"
  list(params = sim$params, err = best_err, status = status, marginals = best_m, history = history)
}
