#!/usr/bin/env Rscript
# Entry point: run the RAVE causal-DAG simulator end-to-end.
#   Rscript run_rave.R [N] [SEED] [OUT_DIR] [PARAMS.json]
# Works under Rscript and source().

## bootstrap: find the skill root (the folder holding R/ + vendor/) and load the engine ---------------------
local({
  self <- NULL
  for (i in rev(seq_len(sys.nframe()))) { of <- sys.frame(i)$ofile; if (!is.null(of)) { self <- of; break } }
  if (is.null(self)) { a <- commandArgs(FALSE); m <- grep("^--file=", a, value = TRUE); if (length(m)) self <- sub("^--file=", "", m[1]) }
  d <- if (!is.null(self)) dirname(normalizePath(self)) else normalizePath(getwd())
  while (!all(dir.exists(file.path(d, c("R", "vendor"))))) { p <- dirname(d); if (identical(p, d)) stop("ctids: skill root not found (need R/ + vendor/)"); d <- p }
  options(ctids.skill_root = d)
  for (f in sort(list.files(file.path(d, "R"), pattern = "\\.R$", full.names = TRUE))) source(f)
})

# source the RAVE example modules in dependency order
.rave_dir <- skill_file("examples", "autoimmune", "rave")
for (f in c("dag_state.R", "rave_params.R", "rave_baseline.R", "rave_longitudinal.R",
            "rave_outcomes.R", "rave_emit.R", "rave_metrics.R", "rave.R"))
  source(file.path(.rave_dir, f))

if (sys.nframe() == 0L) {   # only when run as a script, not sourced
  a <- commandArgs(trailingOnly = TRUE)
  N      <- if (length(a) >= 1) as.integer(a[1]) else 197L
  SEED   <- if (length(a) >= 2) as.integer(a[2]) else 20100715L
  OUT    <- if (length(a) >= 3) a[3] else NULL
  PARAMS <- if (length(a) >= 4) rave_load_params(a[4]) else NULL
  sim <- RaveSim$new(params = PARAMS)
  outdir <- OUT %||% sim$default_out_dir()
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  # copy the shipped Step-2/3 docs into the output bundle so the manifest + HTML render pick them up
  for (doc in c("DAG.md", "CRF_spec.md")) {
    src <- file.path(.rave_dir, doc)
    if (file.exists(src)) file.copy(src, file.path(outdir, doc), overwrite = TRUE)
  }
  res <- sim$run(n_patients = N, seed = SEED, out_dir = outdir, verify = TRUE, render_html = TRUE)
  # copy the Step-2 CRF schema in and try to build the ODM v2.0 export
  # (needs python3 with vendor/python/requirements.txt; skipped cleanly if that's missing).
  picks_src <- file.path(.rave_dir, "odm", "crf_picks.json")
  odm_ok <- FALSE
  if (file.exists(picks_src)) {
    dir.create(file.path(outdir, "odm"), recursive = TRUE, showWarnings = FALSE)
    picks <- file.path(outdir, "odm", "crf_picks.json"); file.copy(picks_src, picks, overwrite = TRUE)
    odm_ok <- tryCatch({
      tpl <- odm_build_template(picks, outdir)
      odm_check_columns(picks, file.path(outdir, "crfs"))
      odm_fill(tpl, file.path(outdir, "crfs"), file.path(outdir, "odm", "odm.xml")); TRUE
    }, error = function(e) { message("ODM step skipped (needs python3 with vendor/python/requirements.txt): ", conditionMessage(e)); FALSE })
  }
  cat("RAVE gates all_pass:", isTRUE(res$gates$all_pass),
      " | ODM:", odm_ok, " | index.html:", file.exists(file.path(outdir, "index.html")), "\n")
}
