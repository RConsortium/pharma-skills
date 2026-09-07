# Internal numerical utilities. Nothing here reaches a report cell.

solver_tolerance <- function(scale) {
  round(scale * .Machine$double.eps, 8)
}

solver_step <- function(lo, hi) {
  signif((hi - lo) / 2, 6)
}
