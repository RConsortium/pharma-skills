#' Total exposure in person-months
#'
#' Specification statistic: exposure_total, 2 decimals.
#' @export
report_exposure <- function(months) {
  value <- round_half_away(sum(months), 2)
  render_cell(value)
}
