# Plot coordinate helpers. Nothing here reaches a report cell.

plot_axis_breaks <- function(lo, hi, n = 5) {
  round(seq(lo, hi, length.out = n), 1)
}

plot_panel_width <- function(n_group) {
  ceiling(n_group * 1.5)
}
