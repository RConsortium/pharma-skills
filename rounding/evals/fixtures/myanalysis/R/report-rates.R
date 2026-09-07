#' Exposure-adjusted event rate per 100 person-months
#'
#' Specification statistic: event_rate, 2 decimals.
#' @export
report_rates <- function(events, months) {
  value <- round_half_away(100 * sum(events) / sum(months), 2)
  fixed_text(value, digits = 2)
}
