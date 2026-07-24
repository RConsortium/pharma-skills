# RAVE Step-6 metrics and DAG gates. Mirrors causal_examples/autoimmune/rave/metrics.py.
# Reads the emitted CSVs, not any in-memory state. run_dag_gates returns a list with $all_pass;
# the engine's run() aborts the whole run if any gate fails.
#
# Published results we calibrate to (ClinicalTrials.gov NCT00104299, results section):
#   complete remission @6mo: RTX 63/99=63.6%, CYC 52/98=53.1%
#   leukopenia (other-event):RTX 13/99=13.1%, CYC 39/98=39.8%
#   >=1 serious AE:          RTX 60/99=60.6%, CYC 47/98=48.0%
#   non-completion:          RTX 9/99=9.1%,   CYC 10/98=10.2%

RAVE_TARGETS <- list(
  cr6mo_RTX = 0.636, cr6mo_CYC = 0.531,
  leuko_RTX = 0.131, leuko_CYC = 0.398,
  sae_RTX = 0.606, sae_CYC = 0.480,
  noncomplete_RTX = 0.091, noncomplete_CYC = 0.102
)
RAVE_TOL <- 0.07   # absolute tolerance on proportions

.rave_load <- function(crfs) {
  out <- list()
  for (f in list.files(crfs, pattern = "^RAVE_CRF_.*\\.csv$", full.names = TRUE)) {
    code <- sub("\\.csv$", "", sub("^RAVE_CRF_", "", basename(f)))
    out[[code]] <- readr::read_csv(f, show_col_types = FALSE, progress = FALSE)
  }
  out
}

.arm_mean <- function(df, arm_col, val) { g <- tapply(df[[val]], df[[arm_col]], mean); as.list(g) }

rave_compute_marginals <- function(crfs) {
  d <- .rave_load(crfs); dm <- d$DM; re <- d$RE; ae <- d$AE
  n <- table(dm$ARMCD)
  m <- list(N_RTX = as.integer(n[["RTX"]] %||% 0), N_CYC = as.integer(n[["CYC"]] %||% 0))
  cr <- .arm_mean(re, "ARMCD", "CR6MO");        m$cr6mo_RTX <- cr$RTX %||% 0; m$cr6mo_CYC <- cr$CYC %||% 0
  sae <- .arm_mean(re, "ARMCD", "SERIOUS_AE");  m$sae_RTX <- sae$RTX %||% 0;  m$sae_CYC <- sae$CYC %||% 0
  leuko_ids <- unique(ae$USUBJID[ae$AEDECOD == "LEUKOPENIA"])
  dm$is_leuko <- as.integer(dm$USUBJID %in% leuko_ids)
  lk <- .arm_mean(dm, "ARMCD", "is_leuko");     m$leuko_RTX <- lk$RTX %||% 0; m$leuko_CYC <- lk$CYC %||% 0
  re$nc <- as.integer(re$DISPOSITION != "COMPLETED")
  nc <- .arm_mean(re, "ARMCD", "nc");           m$noncomplete_RTX <- nc$RTX %||% 0; m$noncomplete_CYC <- nc$CYC %||% 0
  fl <- .arm_mean(re, "ANCATYPE", "FLARE_EVENT"); m$flare_PR3 <- fl$PR3 %||% 0; m$flare_MPO <- fl$MPO %||% 0
  m
}

rave_compare_table <- function(m) {
  lapply(names(RAVE_TARGETS), function(k) {
    tgt <- RAVE_TARGETS[[k]]; sim <- m[[k]] %||% NaN
    list(metric = k, target = tgt, sim = round(sim, 3), diff = round(sim - tgt, 3), within = abs(sim - tgt) <= RAVE_TOL)
  })
}

rave_run_dag_gates <- function(crfs) {
  d <- .rave_load(crfs); ae <- d$AE; lb <- d$LB_HEM; re <- d$RE; dm <- d$DM
  gates <- list()

  # Gate 1: AEs match the labs — mean WBC on Leukopenia AE rows is well below the overall mean
  leuko <- ae[ae$AEDECOD == "LEUKOPENIA", c("USUBJID", "VISIT")]
  merged <- merge(leuko, lb[, c("USUBJID", "VISIT", "WBC")], by = c("USUBJID", "VISIT"))
  wbc_at_leuko <- if (nrow(merged)) mean(merged$WBC) else NaN
  wbc_overall <- mean(lb$WBC)
  gates$g1_ae_lab_linkage <- list(
    wbc_at_leukopenia = round(wbc_at_leuko, 2), wbc_overall = round(wbc_overall, 2),
    pass = isTRUE(wbc_at_leuko < 4.0 && wbc_at_leuko < wbc_overall - 1.0))

  # Gate 2: the arm drives myelosuppression (more leukopenia on CYC than RTX)
  leuko_ids <- unique(ae$USUBJID[ae$AEDECOD == "LEUKOPENIA"])
  dm$is_leuko <- as.integer(dm$USUBJID %in% leuko_ids)
  rate <- tapply(dm$is_leuko, dm$ARMCD, mean)
  gates$g2_arm_myelosuppression <- list(
    leuko_CYC = round(rate[["CYC"]] %||% 0, 3), leuko_RTX = round(rate[["RTX"]] %||% 0, 3),
    pass = isTRUE((rate[["CYC"]] %||% 0) > (rate[["RTX"]] %||% 0)))

  # Gate 3: a patient's GI AEs correlate with each other (they share the f_GI frailty)
  gi <- ae[ae$AEDECOD %in% c("NAUSEA", "VOMITING", "DIARRHOEA"), ]
  ids <- unique(gi$USUBJID)
  if (length(ids) > 5) {
    nau <- vapply(ids, function(u) sum(gi$USUBJID == u & gi$AEDECOD == "NAUSEA"), numeric(1))
    vom <- vapply(ids, function(u) sum(gi$USUBJID == u & gi$AEDECOD == "VOMITING"), numeric(1))
    r <- if (sd(nau) > 0 && sd(vom) > 0) cor(nau, vom) else NaN
  } else r <- NaN
  gates$g3_gi_within_patient_corr <- list(r_nausea_vomiting = round(r, 3), pass = isTRUE(r > 0.0))

  # Gate 4: the primary endpoint really comes from the trajectory (recompute cr6mo from DA + GC at V8 and check it matches)
  da <- d$DA; gc <- d$GC
  v8 <- da[da$VISIT == "V8", ]; gc8 <- gc[gc$VISIT == "V8", ]
  bmap <- setNames(v8$BVASWG, v8$USUBJID); pmap <- setNames(gc8$PREDDOSE, gc8$USUBJID)
  cr <- setNames(re$CR6MO, re$USUBJID)
  agree <- mean(vapply(re$USUBJID, function(u) {
    b <- unname(bmap[u]); p <- unname(pmap[u])   # single-bracket indexing gives NA when the patient has no V8 row
    rec <- if (!is.na(b) && !is.na(p)) as.integer(b == 0.0 && p == 0.0) else 0L
    as.numeric(rec == unname(cr[u]))
  }, numeric(1)))
  gates$g4_endpoint_is_trajectory <- list(agreement = round(agree, 3), pass = isTRUE(agree > 0.98))

  # Gate 5: the stratifier moves the outcome the right way (PR3 flares >= MPO flares)
  fl <- tapply(re$FLARE_EVENT, re$ANCATYPE, mean)
  gates$g5_pr3_higher_flare <- list(
    flare_PR3 = round(fl[["PR3"]] %||% 0, 3), flare_MPO = round(fl[["MPO"]] %||% 0, 3),
    pass = isTRUE((fl[["PR3"]] %||% 0) >= (fl[["MPO"]] %||% 0)))

  # Gate 6 (issue #184): every AE-driven discontinuation traces back to a withdrawn AE, matched on DSTERM == ADVERSE EVENT
  ds <- d$DS
  D <- unique(ds$USUBJID[toupper(as.character(ds$DSTERM)) == "ADVERSE EVENT"])
  wd <- ae[toupper(as.character(ae$AEACN)) == "DRUG WITHDRAWN", ]
  W <- unique(wd$USUBJID); wc <- table(wd$USUBJID)
  gates$g6_ae_ds_traceability <- list(
    n_ds_ae = length(D), n_ae_withdrawn = length(W),
    missing_withdrawn = sort(setdiff(D, W)),
    multi_withdrawn = sort(D[vapply(D, function(u) (wc[u] %||% 0) > 1, logical(1))]),
    pass = isTRUE(setequal(D, W) && all(vapply(D, function(u) (as.integer(wc[u]) %||% 0L) == 1L, logical(1)))))

  gates$all_pass <- all(vapply(gates, function(g) isTRUE(g$pass), logical(1)))
  gates
}
