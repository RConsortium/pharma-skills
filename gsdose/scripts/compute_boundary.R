# compute_boundary.R
# Workflow A compute step: efficacy (and optional futility) boundaries via
# gsDose::gsBoundary, one endpoint at a time, from a single config JSON.
#
# Usage:
#   Rscript compute_boundary.R config.json out.json
#
# config.json:
# {
#   "meta": { ...design assumptions, passed through to the results JSON... },
#   "endpoints": [
#     {
#       "name": "OS",
#       "w": [[1,0,0],[...],[...]],      # stage weights, rows = stages (Q10)
#       "h": [h1, h2],                    # cohort weights (Q5); or rows per stage
#       "d": [260, 416, 520],             # events both cohorts per stage (Q9)
#       "d2": [224, 371, 470],            # cohort-2 events per stage
#       "s": 3,                           # testing stages (Q7)
#       "planD": 520,                     # planned FA events (Q9)
#       "alpha": 0.025,                   # assigned alpha (Q11a)
#       "sf": "OF",                       # 'OF' or 'HSD' (Q11b)
#       "sfpar": null,                    # gamma, required when sf='HSD'
#       "futility": {"enabled": true, "total": 0.975, "sf": "HSD", "sfpar": -6},
#       "alpha_sensitivity": [0.024, 0.025],    # optional extra alpha levels; each
#                                               # gets its own boundary set (futility
#                                               # spends 1 - that alpha, same sf/sfpar)
#       "expected_time": [52.3, 76.7, 102.5]   # optional, from compute_w_weights.R
#     }
#   ]
# }
#
# Output: results JSON = meta + per-endpoint stage table
# (stage, d, d1, d2, info_frac, z_upper, nominal_p_upper, z_lower) ready for
# gsdose_report_template.py.

suppressPackageStartupMessages({
  library(gsDose)
  library(jsonlite)
})

null_or <- function(x, default) if (is.null(x)) default else x

num_vec <- function(x) as.numeric(unlist(x))

num_mat <- function(x) {
  # x parsed with simplifyVector=FALSE: list of rows, or a flat numeric list
  if (is.list(x) && length(x) > 0 && is.list(x[[1]]) == FALSE && length(x[[1]]) > 1) {
    # ambiguous; fall through to rbind below
  }
  if (is.list(x) && all(vapply(x, function(r) is.list(r) || length(r) > 1, TRUE))) {
    do.call(rbind, lapply(x, num_vec))
  } else {
    matrix(num_vec(x), nrow = 1)
  }
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript compute_boundary.R config.json out.json")
cfg <- fromJSON(args[1], simplifyVector = FALSE)

results <- list()

for (i in seq_along(cfg$endpoints)) {
  ep <- cfg$endpoints[[i]]

  w     <- num_mat(ep$w)
  h_raw <- ep$h
  # h: either a single pair [h1,h2] or rows per stage
  if (is.list(h_raw) && length(h_raw) > 0 && is.list(h_raw[[1]])) {
    h <- do.call(rbind, lapply(h_raw, num_vec))
  } else {
    # single pair: replicate across observed stages (same h at every analysis,
    # the package's conventional choice)
    h <- matrix(rep(num_vec(h_raw), each = length(unlist(ep$d))), ncol = 2)
  }
  d     <- num_vec(ep$d)
  d2    <- num_vec(ep$d2)
  s     <- as.integer(ep$s)
  planD <- as.numeric(ep$planD)
  alpha <- as.numeric(ep$alpha)
  sf    <- ep$sf
  sfpar <- if (is.null(ep$sfpar)) NULL else as.numeric(ep$sfpar)

  up <- gsBoundary(w, h, d, d2, s = s, planD = planD,
                   alpha = alpha, sf = sf, sfpar = sfpar, bt = "upper")

  stage_tbl <- data.frame(
    stage           = up$Z$stage,
    d               = d,
    d1              = d - d2,
    d2              = d2,
    info_frac       = round(d / planD, 4),
    z_upper         = round(up$Z$Zbound, 4),
    nominal_p_upper = signif(pnorm(up$Z$Zbound, lower.tail = FALSE), 4)
  )

  fut <- ep$futility
  fut_enabled <- !is.null(fut) && isTRUE(null_or(fut$enabled, FALSE))
  if (fut_enabled) {
    fsfpar <- if (is.null(fut$sfpar)) NULL else as.numeric(fut$sfpar)
    lo <- gsBoundary(w, h, d, d2, s = s, planD = planD,
                     alpha = as.numeric(fut$total), sf = fut$sf,
                     sfpar = fsfpar, bt = "lower")
    stage_tbl$z_lower <- round(lo$Z$Zbound, 4)
  }

  if (!is.null(ep$expected_time))
    stage_tbl$expected_time <- round(num_vec(ep$expected_time), 1)

  # optional sensitivity view: boundaries at additional alpha levels
  sens <- NULL
  if (!is.null(ep$alpha_sensitivity)) {
    alphas_x <- num_vec(ep$alpha_sensitivity)
    sens <- lapply(alphas_x, function(a_k) {
      up_k <- gsBoundary(w, h, d, d2, s = s, planD = planD,
                         alpha = a_k, sf = sf, sfpar = sfpar, bt = "upper")
      stg <- data.frame(
        stage           = up_k$Z$stage,
        z_upper         = round(up_k$Z$Zbound, 4),
        nominal_p_upper = signif(pnorm(up_k$Z$Zbound, lower.tail = FALSE), 4)
      )
      if (fut_enabled) {
        fsfpar_k <- if (is.null(fut$sfpar)) NULL else as.numeric(fut$sfpar)
        lo_k <- gsBoundary(w, h, d, d2, s = s, planD = planD,
                           alpha = 1 - a_k, sf = fut$sf,
                           sfpar = fsfpar_k, bt = "lower")
        stg$z_lower <- round(lo_k$Z$Zbound, 4)
      }
      list(alpha = a_k, stages = stg)
    })
  }

  results[[i]] <- list(
    name     = null_or(ep$name, paste0("endpoint_", i)),
    s        = s,
    planD    = planD,
    alpha    = alpha,
    sf       = sf,
    sfpar    = null_or(sfpar, NA),
    futility = fut,
    h        = h,
    w        = w,
    stages   = stage_tbl,
    sensitivity = sens
  )
}

out <- list(meta = cfg$meta, endpoints = results)
write_json(out, args[2], pretty = TRUE, digits = NA, auto_unbox = TRUE)
cat("WROTE:", args[2], "\n")
