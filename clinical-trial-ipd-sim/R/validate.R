# Boundary checks that validate but never substitute.
#
# They fail loudly on a bad config or an unknown/out-of-range parameter, but RETURN THE INPUT
# UNCHANGED. The engine keeps reading the original list, so calibration output is never silently
# coerced. Base R only (no extra deps).

# ---- small assert helpers (constrained scalar types) -------------------------------------------
.assert <- function(ok, msg) if (!isTRUE(ok)) stop("ctids validate: ", msg, call. = FALSE)

assert_prob   <- function(x, nm = "value") .assert(is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 0 && x <= 1, sprintf("%s must be a probability in [0,1] (got %s)", nm, format(x)))
assert_pos    <- function(x, nm = "value") .assert(is.numeric(x) && length(x) == 1L && !is.na(x) && x > 0,           sprintf("%s must be > 0 (got %s)", nm, format(x)))
assert_nonneg <- function(x, nm = "value") .assert(is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 0,          sprintf("%s must be >= 0 (got %s)", nm, format(x)))
assert_posint <- function(x, nm = "value") .assert(is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 1 && x == round(x), sprintf("%s must be a positive integer (got %s)", nm, format(x)))

# ---- config check: the subclass's config fields must be present and sane BEFORE any RNG runs ----
validate_config <- function(sim) {
  .assert(is.character(sim$prefix) && length(sim$prefix) == 1L && nzchar(sim$prefix), "prefix must be a non-empty string")
  .assert(is.list(sim$sched) && length(sim$sched) >= 1L, "sched must be a non-empty list of visits")
  .assert(is.numeric(sim$admin_censor_day) && length(sim$admin_censor_day) == 1L && sim$admin_censor_day > 0, "admin_censor_day must be > 0")
  .assert(is.list(sim$emitters) && length(sim$emitters) >= 1L && !is.null(names(sim$emitters)), "emitters must be a non-empty named list")
  .assert(is.numeric(sim$default_n) && length(sim$default_n) == 1L && sim$default_n >= 1, "default_n must be >= 1")
  invisible(sim)
}

# ---- params check: reject unknown param names (a typo net) + optional per-param range checks ----
# allowed : character vector of permitted top-level param names (the typo net). NULL = skip.
# checks  : named list of one-arg assert functions run against params[[name]] when present.
# Returns `params` UNCHANGED.
validate_params <- function(params, allowed = NULL, checks = NULL) {
  .assert(is.list(params), "params must be a named list")
  if (!is.null(allowed)) {
    extra <- setdiff(names(params), allowed)
    .assert(length(extra) == 0L, paste0("unknown params (extra not allowed): ", paste(extra, collapse = ", ")))
  }
  if (!is.null(checks)) for (nm in names(checks)) if (!is.null(params[[nm]])) checks[[nm]](params[[nm]])
  params
}
