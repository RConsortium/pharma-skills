# testthat setup: find the skill root, load the engine and both worked examples, and check whether a
# python3 with the needed packages is available (the ODM/render tests skip cleanly when it isn't).

local({
  self <- NULL
  for (i in rev(seq_len(sys.nframe()))) { of <- sys.frame(i)$ofile; if (!is.null(of)) { self <- of; break } }
  if (is.null(self)) { a <- commandArgs(FALSE); m <- grep("^--file=", a, value = TRUE); if (length(m)) self <- sub("^--file=", "", m[1]) }
  d <- if (!is.null(self)) dirname(normalizePath(self)) else normalizePath(getwd())
  while (!all(dir.exists(file.path(d, c("R", "vendor"))))) { p <- dirname(d); if (identical(p, d)) stop("ctids: skill root not found"); d <- p }
  options(ctids.skill_root = d)
  for (f in sort(list.files(file.path(d, "R"), pattern = "\\.R$", full.names = TRUE))) source(f)
})

rdir <- skill_file("examples", "autoimmune", "rave")
for (f in c("dag_state.R", "rave_params.R", "rave_baseline.R", "rave_longitudinal.R",
            "rave_outcomes.R", "rave_emit.R", "rave_metrics.R", "rave.R")) source(file.path(rdir, f))
cdir <- skill_file("examples", "allergy", "cath")
for (f in c("cath_dag_state.R", "cath_graders.R", "cath_params.R", "cath_baseline.R",
            "cath_longitudinal.R", "cath_outcomes.R", "cath_emit.R", "cath_gates.R", "cath_metrics.R", "cath.R"))
  source(file.path(cdir, f))
source(file.path(skill_file("examples", "stub"), "stub.R"))

# check for a python3 with the needed packages (used by the ODM/render tests that shell out)
PY_OK <- tryCatch({
  py <- skill_python()
  identical(as.integer(system2(py, c("-c", shQuote("import lxml, duckdb")), stdout = FALSE, stderr = FALSE)), 0L)
}, error = function(e) FALSE)
