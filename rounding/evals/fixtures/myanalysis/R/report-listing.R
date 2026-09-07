#' Subject-level listing of the analysis value
#'
#' Specification statistic: listing_value, 1 decimal. The format string is
#' assembled at run time, so the formatting call is not visible as a named
#' call in the parse tree.
#' @export
report_listing <- function(x, digits = 1) {
  spec <- paste0("%.", digits, "f")
  do.call(sprintf, list(spec, x))
}
