# TrialSim — the shared R6 simulator engine (ports causal_examples/_base/trial_sim.py).
#
# Everything here is the SAME for every trial. A trial subclass sets a few config fields and
# implements three hooks (make_baseline / simulate_trajectory / derive_endpoints); it inherits:
#   run()             the per-patient generation loop + CSV writer + fail-closed gates + render
#   simulate_one()    baseline -> trajectory -> endpoints -> reconcile, in that order
#   emit_all()        turn a finished patient into CRF rows (one tibble per form)
#   between()         AE-onset day sampled between visits             (GH issue #182)
#   clamp_actual_day() recorded visit day = nominal + jitter          (GH issue #183)
#   reconcile_ae_ds()  make the disposition reason and the "drug       (GH issue #184)
#                      withdrawn" AE record agree
#
# The main RNG is R's global stream (set.seed(seed) in run()); the trial hooks draw from it via the
# np_* wrappers in rng.R. The date-jitter stream (new_substream, rng.R) is separate, so the #182/#183
# date fixes never shift the main draw order. Keeping the two streams apart is the key correctness rule.
#
# Difference from the Python: Python calls reconcile_ae_ds() from each trial's derive_endpoints; here
# simulate_one() calls it once, centrally (after derive_endpoints), so the #184 guarantee holds for
# every trial and hooks never double-call it. reconcile also carries the 0-SAE fallback (see below).
#
# Depends only on: R6, dplyr, readr, tibble, jsonlite (+ this skill's rng.R / validate.R / render.R).

library(R6)

TrialSim <- R6Class("TrialSim", public = list(
  # ---- config: a subclass sets these -----------------------------------------------------------
  prefix = NULL,            # CSV file prefix, e.g. "RAVE" -> RAVE_CRF_DM.csv
  nct = NULL,               # ClinicalTrials.gov ID for the manifest; NULL -> "n/a"
  sched = NULL,             # visit schedule: list of list(key=, visitnum=, day=, label=)
  admin_censor_day = NULL,  # data-cutoff day
  emitters = NULL,          # named list: form -> function(patient) -> tibble of rows
  default_n = NULL,
  default_seed = NULL,
  out_base = "outputs",     # output dir base (out_base/prefix); run(out_dir=) overrides
  progress_every = 0L,
  allowed_params = NULL,    # names accepted by validate_params (the typo net); NULL = skip
  param_checks = NULL,      # optional named list of one-arg range asserts for validate_params
  fixed_n = NULL,           # set if the sim has a FIXED roster (real-covariate bootstrap); calibrate honours it

  params = NULL,
  initialize = function(params = NULL) {
    self$params <- if (is.null(params)) self$default_params() else params
  },

  # ---- shared orchestration (inherited unchanged) ----------------------------------------------
  # Emitted CSVs go under <out_dir>/crfs/. When manifest=TRUE it also writes <out_dir>/README.md and
  # (if the subclass defines dag_structure()) <out_dir>/dag.json. render_html shells out to the vendored
  # Python renderer (best-effort). Calibration passes render_html=FALSE/manifest=FALSE for its throwaway
  # per-iteration dirs.
  run = function(n_patients = NULL, seed = NULL, out_dir = NULL,
                 verify = TRUE, render_html = TRUE, manifest = TRUE) {
    validate_config(self)                                   # boundary check, before any RNG
    self$params <- validate_params(self$params, self$allowed_params, self$param_checks)
    n    <- if (is.null(n_patients)) self$default_n else n_patients
    seed <- if (is.null(seed)) self$default_seed else seed
    set.seed(seed)                                          # the one main stream; jitter uses its own
    self$seed_emit(seed)
    out  <- if (is.null(out_dir)) self$default_out_dir() else out_dir
    crfs <- file.path(out, "crfs")
    dir.create(crfs, recursive = TRUE, showWarnings = FALSE)
    stale <- list.files(out, pattern = sprintf("^%s_CRF_.*\\.csv$", self$prefix), full.names = TRUE)
    if (length(stale)) unlink(stale)                        # bundle rule: CSVs live only under crfs/

    all_rows <- setNames(vector("list", length(self$emitters)), names(self$emitters))
    patients <- vector("list", n)
    t0 <- Sys.time()
    for (i in seq_len(n)) {
      p <- self$simulate_one(i, seed)
      patients[[i]] <- p
      em <- self$emit_all(p)
      for (form in names(em)) {
        rows <- em[[form]]
        if (!is.null(rows) && nrow(rows) > 0) all_rows[[form]][[length(all_rows[[form]]) + 1L]] <- rows
      }
      if (self$progress_every > 0 && i %% self$progress_every == 0)
        message(sprintf("  Simulated %d/%d patients", i, n))
    }

    frames <- list()
    for (form in names(all_rows)) {
      rows <- all_rows[[form]]
      if (length(rows)) frames[[form]] <- dplyr::bind_rows(rows)
    }
    frames <- self$enforce_applicability(frames)   # blank fields that don't apply to a subject
    saved <- character(0); counts <- integer(0)
    for (form in names(frames)) {
      df <- frames[[form]]
      fname <- sprintf("%s_CRF_%s.csv", self$prefix, form)
      readr::write_csv(df, file.path(crfs, fname), na = "")   # missing/not-collected -> blank cell
      saved <- c(saved, fname); counts[fname] <- nrow(df)
    }
    message(sprintf("Simulated %d patients in %.1fs -> %d CRFs in %s",
                    n, as.numeric(difftime(Sys.time(), t0, units = "secs")), length(saved), crfs))

    res <- list(out_dir = out, crfs_dir = crfs, files = saved, patients = patients, gates = NULL)
    # fail-closed verification: run the DAG gates on the EMITTED CSVs; raise on any failure
    if (verify) {
      res$gates <- self$run_dag_gates(crfs)
      if (!is.null(res$gates) && !isTRUE(res$gates$all_pass)) {
        failed <- names(Filter(function(g) is.list(g) && !isTRUE(g$pass), res$gates))
        stop("DAG gates FAILED (fail-closed): ", paste(failed, collapse = ", "), call. = FALSE)
      }
    }
    if (isTRUE(manifest)) {
      g <- res$gates
      if (is.null(g)) g <- tryCatch(self$run_dag_gates(crfs), error = function(e) NULL)
      self$write_manifest(out, n, seed, counts, g)
      self$write_dag_json(out)
    }
    if (isTRUE(render_html)) tryCatch(render_docs(out), error = function(e) invisible(NULL))
    invisible(res)
  },

  simulate_one = function(subj_num, seed) {
    p   <- self$make_baseline(subj_num)
    jit <- new_substream(seed, subj_num)                    # separate jitter stream (rng.R)
    self$simulate_trajectory(p, jit)
    self$derive_endpoints(p)
    self$reconcile_ae_ds(p)                                 # central #184 guarantee (once trajectory final)
    p
  },

  emit_all = function(patient) {
    setNames(lapply(self$emitters, function(fn) fn(patient)), names(self$emitters))
  },

  # Blank any field that doesn't apply to a subject, per applicability_rules(). Runs once on the
  # assembled frames just before write, so it never shifts the per-patient RNG draw order.
  enforce_applicability = function(frames) {
    rules <- self$applicability_rules()
    dm <- frames[["DM"]]
    if (!length(rules) || is.null(dm)) return(frames)
    for (r in rules) {
      f <- frames[[r$form]]
      if (is.null(f)) next
      dm_rows <- dm[match(f$USUBJID, dm$USUBJID), , drop = FALSE]   # demographics aligned to this form's rows
      applies <- r$applicable(dm_rows)
      for (col in r$cols) if (col %in% names(f)) f[[col]][!applies] <- NA
      frames[[r$form]] <- f
    }
    frames
  },

  default_out_dir = function() file.path(self$out_base, self$prefix),

  # ---- shared date-fix + traceability helpers --------------------------------------------------
  # #182: onset day in (prev_day, day] for a symptom reported at this visit. Uses the jitter stream.
  between = function(jit, prev_day, day) {
    if (day > prev_day) jit$draw(function() np_integers(prev_day + 1L, day + 1L)) else day
  },

  # #183: recorded visit day = nominal + jitter, clamped so recorded dates never reorder.
  # Day <= 1 (study anchor) is never jittered.
  clamp_actual_day = function(jit, day, prev_actual, next_nom, sd) {
    if (day <= 1) return(as.integer(day))
    jittered <- day + round(jit$draw(function() np_normal(0, sd)))
    as.integer(max(prev_actual + 1L, min(jittered, next_nom - 1L)))
  },

  # #184: a patient whose disposition reason is an adverse event carries exactly one AE flagged
  # AEACN="DRUG WITHDRAWN" naming the cause; everyone else carries none. Draws no random numbers — it
  # just makes the existing AE -> withdrawal -> discontinuation link agree. AE records are ENVIRONMENTS,
  # edited in place. Does more than the Python (which only looks at serious AEs): when there is no
  # serious AE on/before exit (a 0-SAE trial like CATH), it falls back to the most recent AE, so the
  # link can still be made.
  reconcile_ae_ds = function(patient) {
    withdrawn <- list()
    for (v in patient$trajectory) for (a in v$aes)
      if (identical(a$AEACN, "DRUG WITHDRAWN")) withdrawn[[length(withdrawn) + 1L]] <- a
    if (identical(patient$discontinuation_reason, "ADVERSE EVENT") && length(patient$trajectory)) {
      last   <- patient$trajectory[[length(patient$trajectory)]]
      cutoff <- max(patient$discontinuation_visit_day %||% last$visit_day, last$actual_day)
      cands <- list()
      for (v in patient$trajectory) for (a in v$aes)
        if (identical(a$AESER, "Y") && a$AEDY <= cutoff) cands[[length(cands) + 1L]] <- a
      if (!length(cands))                                   # 0-SAE fallback: most recent AE on/before exit
        for (v in patient$trajectory) for (a in v$aes)
          if (a$AEDY <= cutoff) cands[[length(cands) + 1L]] <- a
      if (length(cands)) {
        trigger <- cands[[which.max(vapply(cands, function(a) a$AEDY, numeric(1)))]]
        for (a in withdrawn) if (!identical(a, trigger)) a$AEACN <- "DRUG INTERRUPTED"
        trigger$AEACN <- "DRUG WITHDRAWN"
      }
    } else {
      for (a in withdrawn) a$AEACN <- "DRUG INTERRUPTED"
    }
    invisible(patient)
  },

  # ---- per-run MANIFEST: README.md (folder-contents table + reproducibility block) --------------
  write_manifest = function(out_dir, n, seed, counts, gates) {
    L <- c("# Run manifest", "", "## Folder contents", "",
           "| item | detail |", "| --- | --- |",
           "| crfs/ | emitted patient CRF CSVs (below) |")
    for (f in names(counts)) L <- c(L, sprintf("| crfs/%s | %d rows |", f, counts[[f]]))
    for (extra in c("dag.json", "DAG.md", "CRF_spec.md", "intake/", "params/", "analysis/", "odm/"))
      if (file.exists(file.path(out_dir, sub("/$", "", extra))))
        L <- c(L, sprintf("| %s | %s |", extra, if (grepl("/$", extra)) "authored inputs/outputs" else "authored artifact"))
    gate_pass <- if (is.null(gates)) NA else isTRUE(gates$all_pass)
    L <- c(L, "", "## Reproducibility", "", "| field | value |", "| --- | --- |",
           sprintf("| trial | %s |", self$prefix %||% "n/a"),
           sprintf("| NCT | %s |", self$nct %||% "n/a"),
           sprintf("| N patients | %d |", n),
           sprintf("| RNG seed | %s |", as.character(seed)),
           sprintf("| date | %s |", as.character(Sys.Date())),
           sprintf("| gates all_pass | %s |", if (is.na(gate_pass)) "not verified" else if (gate_pass) "PASS" else "FAIL"))
    if (!is.null(gates)) {
      L <- c(L, "", "### Gate detail", "", "| gate | status |", "| --- | --- |")
      for (nm in setdiff(names(gates), "all_pass"))
        L <- c(L, sprintf("| %s | %s |", nm, if (isTRUE(gates[[nm]]$pass)) "PASS" else "FAIL"))
    }
    writeLines(L, file.path(out_dir, "README.md"))
  },

  # machine-readable copy of the DAG — writes out_dir/dag.json ONLY if the subclass overrides dag_structure().
  write_dag_json = function(out_dir) {
    d <- self$dag_structure()
    if (is.null(d)) return(invisible(NULL))
    jsonlite::write_json(d, file.path(out_dir, "dag.json"), auto_unbox = TRUE, pretty = TRUE)
  },
  dag_structure = function() NULL,

  # ---- hooks: a subclass implements these ------------------------------------------------------
  make_baseline       = function(subj_num) stop("not implemented: make_baseline", call. = FALSE),
  simulate_trajectory = function(patient, jit) stop("not implemented: simulate_trajectory", call. = FALSE),
  derive_endpoints    = function(patient) stop("not implemented: derive_endpoints", call. = FALSE),
  seed_emit           = function(seed) invisible(NULL),     # override if emit has its own RNG
  run_dag_gates       = function(crfs_dir) NULL,            # override with the trial's gate harness
  default_params      = function() list(),                  # override if the trial has tunable params
  measure_marginals   = function(out_dir) stop("not implemented: measure_marginals", call. = FALSE),

  # ---- logical consistency: which fields exist, and which value combinations are possible ----------
  # A trial declares rules that tie its demographics/characteristics to the data (see gate_logical_
  # consistency in gates.R). applicability_rules() also drives enforce_applicability() above, so a
  # measurement that can't exist for a subject (e.g. lesional skin in a group with no lesions) is never
  # emitted; the same rules are re-checked fail-closed on the CSVs. consistency_rules() are gate-only.
  # Each applicability rule: list(form, cols, applicable=function(dm_rows) logical vector, label).
  # Each consistency rule:   list(form, ok=function(rows) logical vector, label).
  applicability_rules = function() list(),
  consistency_rules   = function() list()
))
