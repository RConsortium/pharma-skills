#' Mean change from baseline
#'
#' Specification statistic: change_mean, 1 decimal.
#' @export
report_change <- function(x) {
  per_subject <- round_half_away(x, 1)
  value <- mean(per_subject)
  fixed_text(value, digits = 1)
}
