#!/usr/bin/env Rscript
# plot_km_hazard.R — Generate KM comparison and hazard rate plots from
#   digitized coordinates and reconstructed IPD using survival/survminer/bshazard.
#
# Usage:
#   Rscript plot_km_hazard.R <digitized.json> <ipd_combined.csv> <output_dir>
#
# Outputs (written to output_dir):
#   km_comparison.png  — side-by-side digitized vs reconstructed KM
#   hazard_rate.png    — smoothed hazard rate over time (bshazard)

suppressPackageStartupMessages({
  library(jsonlite)
  library(survival)
  library(survminer)
  library(bshazard)
  library(ggplot2)
  library(gridExtra)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript plot_km_hazard.R <digitized.json> <ipd_combined.csv> <output_dir>")
}

json_path  <- args[1]
ipd_path   <- args[2]
output_dir <- args[3]
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# --- Read inputs ---
dat <- fromJSON(json_path)
ipd <- read.csv(ipd_path, stringsAsFactors = FALSE)

curves    <- dat$curves
x_range   <- dat$x_axis$range
y_max     <- dat$y_axis$range[2]
nar_times <- if (!is.null(dat$number_at_risk)) dat$number_at_risk$times else NULL
scale     <- if (y_max > 1) 100 else 1
x_label   <- dat$x_axis$label %||% "Time"
y_label   <- dat$y_axis$label %||% "Survival (%)"
arm_names <- unique(ipd$arm)
arm_colors <- c("#1F77B4", "#D62728", "#2CA02C", "#FF7F0E")[seq_along(arm_names)]
names(arm_colors) <- arm_names

cat(sprintf("IPD: %d patients, %d events, %d arms\n",
            nrow(ipd), sum(ipd$event), length(arm_names)))

# ============================================================================
# Panel A: Digitized KM (step plot from raw coordinates)
# ============================================================================
build_digitized_df <- function(curves, scale) {
  dfs <- lapply(seq_along(curves$name), function(i) {
    pts <- curves$points[[i]]
    data.frame(
      time     = pts$time,
      survival = pts$survival / scale,
      arm      = curves$name[i],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, dfs)
}

dig_df <- build_digitized_df(curves, scale)

p_digitized <- ggplot(dig_df, aes(x = time, y = survival, color = arm)) +
  geom_step(linewidth = 0.8) +
  scale_color_manual(values = arm_colors) +
  scale_y_continuous(labels = scales::percent_format(), limits = c(0, 1.05)) +
  scale_x_continuous(breaks = if (!is.null(nar_times)) nar_times else waiver(),
                     expand = c(0, 0)) +
  coord_cartesian(xlim = c(x_range[1], x_range[2])) +
  labs(x = x_label, y = y_label, title = "Digitized (Original)", color = NULL) +
  theme_bw(base_size = 11) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold", hjust = 0.5)
  )

# ============================================================================
# Panel B: Reconstructed KM from IPD using survfit + ggsurvplot
# ============================================================================
ipd$arm <- factor(ipd$arm, levels = arm_names)
fit <- survfit(Surv(time, event) ~ arm, data = ipd)

ggsurv_obj <- ggsurvplot(
  fit,
  data          = ipd,
  palette       = unname(arm_colors),
  censor        = TRUE,
  censor.size   = 3,
  legend        = "bottom",
  legend.title  = "",
  legend.labs   = arm_names,
  xlab          = x_label,
  ylab          = y_label,
  title         = "Reconstructed (IPD)",
  ggtheme       = theme_bw(base_size = 11),
  surv.scale    = "percent",
  ylim          = c(0, 1.05),
  risk.table    = FALSE
)
p_reconstructed <- ggsurv_obj$plot +
  theme(plot.title = element_text(face = "bold", hjust = 0.5)) +
  scale_x_continuous(breaks = if (!is.null(nar_times)) nar_times else waiver(),
                     expand = c(0, 0),
                     limits = c(x_range[1], x_range[2]))

# --- Save KM comparison ---
km_path <- file.path(output_dir, "km_comparison.png")
png(km_path, width = 12, height = 5, units = "in", res = 300)
grid.arrange(p_digitized, p_reconstructed, ncol = 2)
dev.off()
cat(sprintf("KM comparison: %s\n", km_path))

# ============================================================================
# Hazard rate plot using bshazard
# ============================================================================

# Determine x-axis cutoff: earliest time any arm drops below 20% at risk
at_risk_pct <- 0.20
x_max <- Inf
for (arm_name in arm_names) {
  arm_data <- ipd[ipd$arm == arm_name, ]
  n_total  <- nrow(arm_data)
  km_fit   <- survfit(Surv(time, event) ~ 1, data = arm_data)
  # n.risk from survfit
  below_idx <- which(km_fit$n.risk < at_risk_pct * n_total)
  if (length(below_idx) > 0) {
    cutoff <- km_fit$time[below_idx[1]]
    x_max  <- min(x_max, cutoff)
  }
}
if (is.infinite(x_max)) x_max <- max(ipd$time)
cat(sprintf("Hazard plot cutoff: %.1f months (20%% at-risk threshold)\n", x_max))

# Fit bshazard per arm and collect results
hz_list <- lapply(arm_names, function(arm_name) {
  arm_data <- ipd[ipd$arm == arm_name, ]
  bsh <- bshazard(Surv(time, event) ~ 1, data = arm_data, verbose = FALSE)
  data.frame(
    time    = bsh$time,
    hazard  = bsh$hazard,
    lower   = bsh$lower.ci,
    upper   = bsh$upper.ci,
    arm     = arm_name,
    stringsAsFactors = FALSE
  )
})
hz_df <- do.call(rbind, hz_list)
hz_df$arm <- factor(hz_df$arm, levels = arm_names)

# Truncate to x_max
hz_df <- hz_df[hz_df$time <= x_max, ]

p_hazard <- ggplot(hz_df, aes(x = time, color = arm, fill = arm)) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.15, linetype = 0) +
  geom_line(aes(y = hazard), linewidth = 0.8) +
  scale_color_manual(values = arm_colors) +
  scale_fill_manual(values = arm_colors) +
  scale_x_continuous(breaks = if (!is.null(nar_times)) nar_times[nar_times <= x_max] else waiver(),
                     expand = c(0, 0)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(0, NA)) +
  labs(
    x     = x_label,
    y     = "Hazard Rate",
    title = "Smoothed Hazard Rate Over Time (B-spline)",
    color = NULL,
    fill  = NULL
  ) +
  theme_bw(base_size = 11) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold", hjust = 0.5)
  )

hz_path <- file.path(output_dir, "hazard_rate.png")
ggsave(hz_path, p_hazard, width = 8, height = 5, dpi = 300)
cat(sprintf("Hazard rate: %s\n", hz_path))

cat("Done.\n")
