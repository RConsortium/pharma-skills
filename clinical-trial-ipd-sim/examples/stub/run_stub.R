#!/usr/bin/env Rscript
# Entry point: run the STUB trial. Works under `Rscript run_stub.R` and `source("run_stub.R")`.

## bootstrap: locate skill root (dir with R/ + vendor/) and load the engine ---------------------
local({
  self <- NULL
  for (i in rev(seq_len(sys.nframe()))) { of <- sys.frame(i)$ofile; if (!is.null(of)) { self <- of; break } }
  if (is.null(self)) { a <- commandArgs(FALSE); m <- grep("^--file=", a, value = TRUE); if (length(m)) self <- sub("^--file=", "", m[1]) }
  d <- if (!is.null(self)) dirname(normalizePath(self)) else normalizePath(getwd())
  while (!all(dir.exists(file.path(d, c("R", "vendor"))))) { p <- dirname(d); if (identical(p, d)) stop("ctids: skill root not found (need R/ + vendor/)"); d <- p }
  options(ctids.skill_root = d)
  for (f in sort(list.files(file.path(d, "R"), pattern = "\\.R$", full.names = TRUE))) source(f)
})
source(skill_file("examples", "stub", "stub.R"))

sim <- StubSim$new()
out <- file.path(tempdir(), "STUB_output")
res <- sim$run(out_dir = out, verify = FALSE, render_html = FALSE)  # STUB has no gates or DAG
cat("STUB wrote:", paste(res$files, collapse = ", "), "->", res$crfs_dir, "\n")
