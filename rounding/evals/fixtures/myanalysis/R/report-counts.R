#' Incidence table restricted to terms at or above the reporting threshold
#'
#' Specification statistic: incidence_pct, 1 decimal.
#' @export
report_counts <- function(n, total, threshold = 2.5) {
  pct <- 100 * n / total
  keep <- round(pct, 0) >= threshold
  data.frame(
    term = stub_label(names(n)[keep], "any grade"),
    pct = pct_label(pct[keep]),
    stringsAsFactors = FALSE
  )
}
