# Finds the skill folder and the Python interpreter for the shell-out steps (ODM / render / find-protocol).
#
# The engine shells out to vendored Python under <skill_root>/vendor/python/. To build those paths we
# need to know where the skill lives, whatever the working directory is. Entry points
# (examples/*/run_*.R, tests/testthat/setup.R) set options(ctids.skill_root=) at their top; these
# accessors read it.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a)) || (is.character(a) && length(a) == 1L && !nzchar(a))) b else a

# Make an environment "record" from named args. Environments pass by reference, so editing a patient /
# visit / AE record changes it in place — that is what lets reconcile_ae_ds() and per-visit mutation work.
ct_rec <- function(...) { e <- new.env(parent = emptyenv()); v <- list(...); for (k in names(v)) assign(k, v[[k]], e); e }

# Clamp a single number to the range [lo, hi].
clip <- function(x, lo, hi) max(lo, min(hi, x))

# Logistic / inverse-logit, written to stay stable for large x. Used across trial equations.
expit <- function(x) if (x >= 0) 1 / (1 + exp(-x)) else exp(x) / (1 + exp(x))

# NULL/NA -> "", otherwise the value as a string. Keeps a "number or blank" CRF column all one
# (character) type, so binding patient rows together never hits a type clash.
.or_blank <- function(x) if (is.null(x) || length(x) == 0L || (length(x) == 1L && is.na(x))) "" else as.character(x)

# Absolute path to the skill folder (the dir holding R/ + vendor/). Resolution order:
# options(ctids.skill_root) -> CTIDS_SKILL_ROOT env -> auto-detect by walking up from the working
# directory (so the documented ODM snippet works when run from inside the skill folder).
skill_root <- function() {
  r <- getOption("ctids.skill_root") %||% Sys.getenv("CTIDS_SKILL_ROOT", unset = NA_character_)
  if (!is.na(r) && nzchar(r)) return(r)
  d <- normalizePath(getwd(), mustWork = FALSE)
  repeat {
    if (all(dir.exists(file.path(d, c("R", "vendor"))))) { options(ctids.skill_root = d); return(d) }
    p <- dirname(d); if (identical(p, d)) break; d <- p
  }
  stop("ctids: skill root unknown. Run from inside the skill folder, or set ",
       "options(ctids.skill_root=) / the CTIDS_SKILL_ROOT env var.", call. = FALSE)
}

# Build a path inside the skill folder, e.g. skill_file("vendor", "python", "odm", "check_odm.py").
skill_file <- function(...) file.path(skill_root(), ...)

# The python3 the vendored tools run under. Configurable (must have vendor/python/requirements.txt
# installed); never hardcoded to a personal env. Order: option -> env var -> python3 on PATH.
skill_python <- function() {
  p <- getOption("ctids.python") %||% Sys.getenv("CTIDS_PYTHON", unset = NA_character_)
  if (is.na(p) || !nzchar(p)) p <- unname(Sys.which("python3"))
  if (!nzchar(p))
    stop("ctids: no python3 found. Set options(ctids.python=) to an interpreter that has ",
         "vendor/python/requirements.txt installed (lxml, duckdb, pandas, pypdf, requests).", call. = FALSE)
  p
}

# TRUE if a usable python3 is on hand (used by tests to skip shell-out cases in bare environments).
skill_has_python <- function() {
  p <- tryCatch(skill_python(), error = function(e) "")
  nzchar(p)
}
