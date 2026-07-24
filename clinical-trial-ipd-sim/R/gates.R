# Reference realism/traceability gate harness (ports templates/verify_realism.py). These are the
# machine realism/date gates for issues #182/#183/#184. A NEW trial adapts them by setting the
# column/form names in gate_config(); the gate LOGIC stays identical across trials, which is what
# makes the fixes enforceable rather than re-derived each time. CATH's examples/allergy/cath/
# cath_gates.R is a worked adaptation (with 4 extra CATH causal gates); RAVE folds the #184 check into
# its own causal gates (rave_metrics.R).
#
# Two hard rules: gates read the EMITTED CSVs (never engine state); the AE<->DS gate keys on the
# emitted REASON field (DSTERM), not the disposition code. Returns per-gate lists with $pass; run_all
# reduces to $all_pass. Reads {prefix}_CRF_{form}.csv under crfs_dir.

# Per-trial adaptation layer. Set crfs_dir + nominal_days (+ nominal_by_visit); override names as needed.
gate_config <- function(crfs_dir, nominal_days, prefix = "",
                        visit_form = "LB", visit_col = "VISIT", visit_day_col = "LBDY",
                        ae_form = "AE", ae_day_col = "AEDY", ae_action_col = "AEACN", ae_serious_col = "AESER",
                        ds_form = "DS", ds_reason_col = "DSTERM", ds_day_col = "DSDY",
                        completed_value = "COMPLETED STUDY", ae_reason_value = "ADVERSE EVENT",
                        withdrawn_value = "DRUG WITHDRAWN", nominal_by_visit = list()) {
  list(crfs_dir = crfs_dir, nominal_days = nominal_days, prefix = prefix,
       visit_form = visit_form, visit_col = visit_col, visit_day_col = visit_day_col,
       ae_form = ae_form, ae_day_col = ae_day_col, ae_action_col = ae_action_col, ae_serious_col = ae_serious_col,
       ds_form = ds_form, ds_reason_col = ds_reason_col, ds_day_col = ds_day_col,
       completed_value = completed_value, ae_reason_value = ae_reason_value,
       withdrawn_value = withdrawn_value, nominal_by_visit = nominal_by_visit)
}

.gates_load <- function(cfg, form) {
  fn <- if (nzchar(cfg$prefix)) sprintf("%s_CRF_%s.csv", cfg$prefix, form) else sprintf("%s.csv", form)
  readr::read_csv(file.path(cfg$crfs_dir, fn), show_col_types = FALSE, progress = FALSE)
}

# #183a — recorded visit dates must not all snap to the nominal grid
gate_visit_date_variance <- function(cfg, min_sd = 0.5) {
  df <- .gates_load(cfg, cfg$visit_form)
  if (length(cfg$nominal_by_visit)) {
    df$._nom <- unlist(cfg$nominal_by_visit[as.character(df[[cfg$visit_col]])])
    df <- df[!is.na(df$._nom), ]
    delta <- df[[cfg$visit_day_col]] - df$._nom
  } else {
    delta <- ave(df[[cfg$visit_day_col]], df[[cfg$visit_col]], FUN = function(s) s - median(s))
  }
  sd_ <- sd(delta)
  list(visit_date_sd = round(sd_, 2), pass = isTRUE(sd_ > min_sd))
}

# #182 — symptomatic AE onsets fall between visits (many distinct off-grid days), not all on the grid
gate_ae_onset_dispersion <- function(cfg, min_ratio = 2.0) {
  ae <- .gates_load(cfg, cfg$ae_form)
  distinct <- length(unique(ae[[cfg$ae_day_col]]))
  off_grid <- mean(!(ae[[cfg$ae_day_col]] %in% cfg$nominal_days))
  n_visits <- max(1L, length(cfg$nominal_days))
  list(distinct_onset_days = distinct, n_nominal_visits = n_visits, frac_off_grid = round(off_grid, 2),
       pass = isTRUE(distinct > min_ratio * n_visits && off_grid > 0.3))
}

# #183b — discontinuation falls on off-grid days AND cannot come before its cause
gate_discontinuation_continuous <- function(cfg, min_off_grid = 0.3) {
  ds <- .gates_load(cfg, cfg$ds_form)
  disc <- ds[toupper(trimws(as.character(ds[[cfg$ds_reason_col]]))) != toupper(cfg$completed_value), ]
  off_grid <- if (nrow(disc)) mean(!(disc[[cfg$ds_day_col]] %in% cfg$nominal_days)) else 1.0
  ae <- .gates_load(cfg, cfg$ae_form)
  wd <- ae[toupper(as.character(ae[[cfg$ae_action_col]])) == toupper(cfg$withdrawn_value), ]
  before_cause <- 0L
  if (nrow(wd) && nrow(disc)) {
    trig <- tapply(wd[[cfg$ae_day_col]], wd$USUBJID, max); exitd <- tapply(disc[[cfg$ds_day_col]], disc$USUBJID, max)
    common <- intersect(names(trig), names(exitd))
    if (length(common)) before_cause <- sum(vapply(common, function(u) exitd[[u]] < trig[[u]], logical(1)))
  }
  list(frac_disc_off_grid = round(off_grid, 2), exits_before_their_cause = before_cause,
       pass = isTRUE(off_grid > min_off_grid && before_cause == 0L))
}

# #184 — AE<->DS traceability (keyed on the emitted reason field)
gate_ae_ds_traceability <- function(cfg) {
  ds <- .gates_load(cfg, cfg$ds_form); ae <- .gates_load(cfg, cfg$ae_form)
  D <- unique(ds$USUBJID[toupper(as.character(ds[[cfg$ds_reason_col]])) == toupper(cfg$ae_reason_value)])
  wd <- ae[toupper(as.character(ae[[cfg$ae_action_col]])) == toupper(cfg$withdrawn_value), ]
  W <- unique(wd$USUBJID); per <- table(wd$USUBJID)
  list(n_ds_ae = length(D), n_ae_withdrawn = length(W),
       missing_withdrawn = sort(setdiff(D, W)), stray_withdrawn = sort(setdiff(W, D)),
       multi_withdrawn = sort(D[vapply(D, function(u) (per[u] %||% 0) > 1, logical(1))]),
       pass = isTRUE(setequal(D, W) && all(vapply(D, function(u) (as.integer(per[u]) %||% 0L) == 1L, logical(1)))))
}

# Logical consistency — a subject's demographics/characteristics must map to the data. This is the
# general guardrail behind "some measurements don't exist for some people, and impossible combinations
# must never appear". A trial declares rules keyed to its demographics (the DM form); this reads the
# emitted CSVs, joins each governed form to DM by USUBJID, and fails closed on any violation. Two kinds:
#   applicability  list(form, cols, applicable, label): each col must be FILLED when applicable(dm) is
#                  TRUE and BLANK otherwise (dm = DM covariates aligned to the form's rows; applicable
#                  returns a logical vector). Catches a value where the measurement can't exist AND a
#                  blank where it should. These same rules drive enforce_applicability() in the engine.
#   consistency    list(form, ok, label): ok(rows) must hold for every row (rows = the form joined to
#                  its DM covariates) — e.g. age within eligibility, no pregnancy record for a male.
gate_logical_consistency <- function(crfs_dir, prefix, applicability = list(), consistency = list()) {
  load <- function(form) {
    f <- file.path(crfs_dir, sprintf("%s_CRF_%s.csv", prefix, form))
    if (file.exists(f)) readr::read_csv(f, show_col_types = FALSE, progress = FALSE) else NULL
  }
  is_blank <- function(x) is.na(x) | trimws(as.character(x)) == ""
  dm <- load("DM")
  with_dm <- function(f) {                        # add the DM covariates this form doesn't already carry
    if (is.null(dm)) return(f)
    add <- setdiff(names(dm), names(f))
    cbind(f, dm[match(f$USUBJID, dm$USUBJID), add, drop = FALSE])
  }
  detail <- list(); violations <- 0L
  for (r in applicability) {
    f <- load(r$form); if (is.null(f) || is.null(dm)) next
    applies <- r$applicable(dm[match(f$USUBJID, dm$USUBJID), , drop = FALSE])
    value_where_inapplicable <- 0L; blank_where_applicable <- 0L
    for (col in r$cols) if (col %in% names(f)) {
      b <- is_blank(f[[col]])
      value_where_inapplicable <- value_where_inapplicable + sum(!applies & !b)
      blank_where_applicable   <- blank_where_applicable   + sum(applies & b)
    }
    violations <- violations + value_where_inapplicable + blank_where_applicable
    detail[[r$label]] <- list(kind = "applicability", form = r$form,
                              value_where_inapplicable = value_where_inapplicable,
                              blank_where_applicable = blank_where_applicable)
  }
  for (r in consistency) {
    f <- load(r$form); if (is.null(f)) next
    ok <- r$ok(with_dm(f)); n <- sum(!ok, na.rm = TRUE)
    violations <- violations + n
    detail[[r$label]] <- list(kind = "consistency", form = r$form, violations = n)
  }
  list(n_rules = length(applicability) + length(consistency),
       violations = violations, detail = detail, pass = isTRUE(violations == 0L))
}

run_realism_gates <- function(cfg) {
  gates <- list(
    g_visit_date_variance        = gate_visit_date_variance(cfg),
    g_ae_onset_dispersion        = gate_ae_onset_dispersion(cfg),
    g_discontinuation_continuous = gate_discontinuation_continuous(cfg),
    g_ae_ds_traceability         = gate_ae_ds_traceability(cfg))
  gates$all_pass <- all(vapply(gates, function(g) isTRUE(g$pass), logical(1)))
  gates
}
