#' Confidence interval for the risk difference
#'
#' The display specification has no entry for this statistic, so the
#' required precision comes from the caller.
#' @export
report_ci <- function(lower, upper, digits) {
  paste0("(", fixed_text(lower, digits), ", ", fixed_text(upper, digits), ")")
}
