# compute_event_prob.R
# Compute per-patient event probability at a given analysis time,
# properly integrating over the enrollment distribution.
#
# Use this for multi-population designs to derive N from events:
#   N_total = events / compute_event_prob(...) / prevalence
#
# Do NOT use nSurv() or gsSurv() for subpopulation N derivation —
# they treat the subgroup as an independent trial and can oversize.
#
# Supports both constant and piecewise exponential control hazards.
#
# Usage:
#   source("<skill_path>/scripts/compute_event_prob.R")
#   p <- compute_event_prob(analysis_time=35, lambdaC=log(2)/8, hr=0.69,
#                           eta=-log(1-0.02)/12, gamma_vec=c(5,20,30),
#                           R_vec=c(2,3,18))
#   N_sub <- ceiling(events_FA / p)
#   N_total <- ceiling(N_sub / prevalence)

compute_event_prob <- function(analysis_time, lambdaC, hr, eta,
                                gamma_vec, R_vec, ratio = 1,
                                S = NULL, n_quad = 50) {
  # Cumulative hazard function (handles piecewise)
  cum_hazard <- function(t, lambda_vec, S_vec) {
    if (is.null(S_vec) || length(lambda_vec) == 1) {
      return(lambda_vec[1] * t)
    }
    breaks <- c(0, S_vec, Inf)
    H <- 0
    for (j in seq_along(lambda_vec)) {
      t_lo <- breaks[j]
      t_hi <- min(t, breaks[j + 1])
      if (t_lo >= t) break
      H <- H + lambda_vec[j] * (t_hi - t_lo)
    }
    H
  }

  # Treatment hazard vector = lambdaC * hr (proportional hazards)
  lambdaE <- lambdaC * hr

  # Enrollment period boundaries
  enroll_starts <- c(0, cumsum(R_vec[-length(R_vec)]))
  enroll_ends   <- cumsum(R_vec)

  # Numerical integration: for each enrollment period, compute average
  # event probability across patients enrolled in that period
  total_weight  <- 0
  weighted_prob <- 0

  for (i in seq_along(gamma_vec)) {
    s_start <- enroll_starts[i]
    s_end   <- min(enroll_ends[i], analysis_time)
    if (s_start >= analysis_time) next

    rate <- gamma_vec[i]
    dur  <- s_end - s_start
    n_pts_in_period <- round(rate * dur)
    if (n_pts_in_period == 0) next

    # Quadrature points (midpoints of sub-intervals)
    t_enroll <- seq(s_start, s_end, length.out = n_quad + 1)
    t_mid <- (t_enroll[-1] + t_enroll[-(n_quad + 1)]) / 2

    for (t_e in t_mid) {
      fup <- analysis_time - t_e
      if (fup <= 0) next

      # Survival for control and treatment arms
      H_ctrl <- cum_hazard(fup, lambdaC, S)
      H_trt  <- cum_hazard(fup, lambdaE, S)
      s_ctrl <- exp(-H_ctrl - eta * fup)
      s_trt  <- exp(-H_trt  - eta * fup)

      # P(event) averaged across arms weighted by allocation ratio
      p_ctrl <- 1 - s_ctrl
      p_trt  <- 1 - s_trt
      p_avg  <- (p_ctrl / (1 + ratio)) + (p_trt * ratio / (1 + ratio))

      weighted_prob <- weighted_prob + p_avg
      total_weight  <- total_weight + 1
    }
  }

  if (total_weight == 0) return(0)
  weighted_prob / total_weight
}


# Convenience wrapper: compute N_total from required events and prevalence
# Returns a list with event_prob, N_sub, N_total
compute_N_from_events <- function(events_FA, analysis_time, lambdaC, hr, eta,
                                   gamma_vec, R_vec, prevalence = 1.0,
                                   ratio = 1, S = NULL) {
  p <- compute_event_prob(analysis_time, lambdaC, hr, eta,
                           gamma_vec, R_vec, ratio, S)
  N_sub   <- ceiling(events_FA / p)
  N_total <- ceiling(N_sub / prevalence)
  list(event_prob = p, N_sub = N_sub, N_total = N_total)
}
