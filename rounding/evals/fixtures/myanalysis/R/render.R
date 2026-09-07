# Cell renderers.

#' Fixed-width character output that preserves trailing zeros
fixed_text <- function(x, digits) {
  formatC(x, format = "f", digits = digits)
}

#' Render a numeric cell for the table body
#'
#' Returns the shortest numeric text, so 76 at a two-decimal specification
#' renders as "76" rather than "76.00".
render_cell <- function(x) {
  as.character(x)
}

#' Join a label and a value for the table stub
stub_label <- function(term, level) {
  paste0(term, " (", as.character(level), ")")
}
