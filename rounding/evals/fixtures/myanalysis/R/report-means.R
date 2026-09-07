#' Mean percentage of subjects with an event
#'
#' Specification statistic: mean_pct, 0 decimals.
#' @export
report_means <- function(pct) {
  value <- round(mean(pct), 0)
  fixed_text(value, digits = 0)
}
