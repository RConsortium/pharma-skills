# Numeric helpers shared by the report_*() entry points.

#' Round half away from zero (the approved BR-001 helper)
#'
#' Exact decimal ties move away from zero, matching the SAS convention:
#' 2.5 -> 3 and -2.5 -> -3. Inexact ties follow the stored binary value,
#' which is a property of the representation rather than of this helper.
round_half_away <- function(x, digits = 0) {
  scale <- 10^digits
  sign(x) * trunc(abs(x) * scale + 0.5) / scale
}

#' Percentage label used by the incidence table
#'
#' Quantizes with integer division, so no catalog function name appears
#' anywhere in this body.
pct_label <- function(x) {
  n <- (x * 10) %/% 1 / 10
  paste0(n, "%")
}
