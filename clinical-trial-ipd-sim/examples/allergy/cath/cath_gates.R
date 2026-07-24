# CATH DAG-gate harness — checks on the EMITTED CRFs that fail the run if broken. Ported from
# causal_examples/allergy/cath/verify_dag_gates.py. Four date/traceability gates (#182/#183/#184;
# same logic, columns adapted) plus four CATH causal gates. Two hard rules: gates read the emitted
# CSVs (never the engine's in-memory state), and the AE<->DS gate matches on the reason field
# (DSTERM), not the code.

CATH_NOMINAL_DAYS <- c(-7L, 0L, 21L)
CATH_NOMINAL_BY_VISIT <- list(SCRN = -7L, D21 = 21L)

# Logical-consistency rules: which fields apply given a subject's diagnosis group / sex / age.
# Declared once and used by BOTH the engine (enforce_applicability blanks these fields) and the gate
# below, so the two can never disagree. Non-atopic controls have no lesion, so lesional fields cannot
# exist for them; the pregnancy test is female-only; psoriasis details exist only for that group.
.cath_has_lesion <- function(dm) dm$DIAGGRP %in% c("Psor", "AD")
CATH_APPLICABILITY_RULES <- list(
  list(form = "BX", cols = c("CAMP_LES", "HBD3_LES", "IL13_LES", "IL4_LES"),
       applicable = .cath_has_lesion, label = "lesional biopsy only for groups with lesions"),
  list(form = "TS", cols = c("TS_CAMP_LES", "TS_HBD3_LES"),
       applicable = .cath_has_lesion, label = "lesional tape-strip only for groups with lesions"),
  list(form = "MB", cols = c("CFU_LES"),
       applicable = .cath_has_lesion, label = "lesional microbial count only for groups with lesions"),
  list(form = "DC", cols = c("DXPSOR", "PSORDUR_MO", "PSORSEV"),
       applicable = function(dm) dm$DIAGGRP == "Psor", label = "psoriasis characteristics only for the psoriasis group")
)
CATH_CONSISTENCY_RULES <- list(
  list(form = "PT", ok = function(r) r$SEX == "F", label = "pregnancy test only for female subjects"),
  list(form = "DM", ok = function(r) r$AGE >= 18 & r$AGE <= 70, label = "age within eligibility (18-70)")
)

.cath_gload <- function(crfs, name) readr::read_csv(file.path(crfs, paste0("CATH_CRF_", name, ".csv")), show_col_types = FALSE, progress = FALSE)

.cath_symptomatic <- function(ae) {
  is_gi <- grepl("Gastrointestinal", as.character(ae$AEBODSYS), ignore.case = TRUE)
  is_wd <- toupper(as.character(ae$AEACN)) == "DRUG WITHDRAWN"
  ae[is_gi | is_wd, ]
}

# ---- #183a visit dates must not all land exactly on the scheduled days ----
cath_gate_visit_date_variance <- function(crfs, min_sd = 0.5) {
  df <- .cath_gload(crfs, "LB")
  df$._nom <- unlist(CATH_NOMINAL_BY_VISIT[as.character(df$VISIT)])
  df <- df[!is.na(df$._nom), ]
  sd_ <- sd(df$LBDY - df$._nom)
  list(visit_date_sd = round(sd_, 3), n_rows = nrow(df), pass = isTRUE(sd_ > min_sd))
}

# ---- #182 symptomatic AE onset days fall between visits, not on visit days ----
cath_gate_ae_onset_dispersion <- function(crfs, min_off_grid = 0.3) {
  ae <- .cath_gload(crfs, "AE"); sym <- .cath_symptomatic(ae); n <- nrow(sym)
  if (n == 0) return(list(n_symptomatic_ae = 0L, frac_off_grid = NA,
                          note = "no between-visit AE at N=82 (AE burden ~0); invariant cannot be violated; confirmed at high N",
                          pass = TRUE))
  off <- mean(!(sym$AEDY %in% CATH_NOMINAL_DAYS))
  list(n_symptomatic_ae = n, frac_off_grid = round(off, 3), distinct_onset_days = length(unique(sym$AEDY)), pass = isTRUE(off > min_off_grid))
}

# ---- #183b discontinuation day is off-grid AND never earlier than the AE that caused it ----
cath_gate_discontinuation_continuous <- function(crfs, min_off_grid = 0.3) {
  ds <- .cath_gload(crfs, "DS")
  disc <- ds[toupper(trimws(as.character(ds$DSTERM))) != "COMPLETED STUDY", ]
  off <- if (nrow(disc)) mean(!(disc$DSSTDY %in% CATH_NOMINAL_DAYS)) else 1.0
  ae <- .cath_gload(crfs, "AE")
  wd <- ae[toupper(as.character(ae$AEACN)) == "DRUG WITHDRAWN", ]
  before_cause <- 0L
  if (nrow(wd) && nrow(disc)) {
    trig <- tapply(wd$AEDY, wd$USUBJID, max); exitd <- tapply(disc$DSSTDY, disc$USUBJID, max)
    common <- intersect(names(trig), names(exitd))
    if (length(common)) before_cause <- sum(vapply(common, function(u) exitd[[u]] < trig[[u]], logical(1)))
  }
  list(n_discontinued = nrow(disc), frac_disc_off_grid = round(off, 3),
       exits_before_their_cause = before_cause, pass = isTRUE(off > min_off_grid && before_cause == 0L))
}

# ---- #184 AE<->DS traceability, matched on the DSTERM reason ----
cath_gate_ae_ds_traceability <- function(crfs) {
  ds <- .cath_gload(crfs, "DS"); ae <- .cath_gload(crfs, "AE")
  D <- unique(ds$USUBJID[toupper(as.character(ds$DSTERM)) == "ADVERSE EVENT"])
  wd <- ae[toupper(as.character(ae$AEACN)) == "DRUG WITHDRAWN", ]
  W <- unique(wd$USUBJID); per <- table(wd$USUBJID)
  list(n_ds_ae = length(D), n_ae_withdrawn = length(W),
       missing_withdrawn = sort(setdiff(D, W)), stray_withdrawn = sort(setdiff(W, D)),
       multi_withdrawn = sort(D[vapply(D, function(u) (per[u] %||% 0) > 1, logical(1))]),
       pass = isTRUE(setequal(D, W) && all(vapply(D, function(u) (as.integer(per[u]) %||% 0L) == 1L, logical(1)))))
}

# ---- causal: endpoint change is derived from the trajectory (BL and D21 CAMP correlate) ----
cath_gate_endpoint_derived <- function(crfs, min_r = 0.4) {
  bx <- .cath_gload(crfs, "BX")
  bl <- bx[bx$VISIT == "BL", c("USUBJID", "CAMP_NONLES")]; d21 <- bx[bx$VISIT == "D21", c("USUBJID", "CAMP_NONLES")]
  m <- merge(bl, d21, by = "USUBJID", suffixes = c("_bl", "_d21"))
  if (nrow(m) <= 5) return(list(r_bl_d21_camp = NA, n = nrow(m), pass = FALSE))
  r <- cor(m$CAMP_NONLES_bl, m$CAMP_NONLES_d21)
  list(r_bl_d21_camp = round(r, 3), n = nrow(m), pass = isTRUE(r > min_r))
}

# ---- causal: arm -> mediator (serum VitD rises more in the VitD arm than placebo) ----
cath_gate_arm_mediator <- function(crfs, min_gap = 2.0) {
  lb <- .cath_gload(crfs, "LB"); dm <- .cath_gload(crfs, "DM")[, c("USUBJID", "ARMCD")]
  scrn <- lb[lb$VISIT == "SCRN", c("USUBJID", "VITD")]; d21 <- lb[lb$VISIT == "D21", c("USUBJID", "VITD")]
  m <- merge(scrn, d21, by = "USUBJID", suffixes = c("_scrn", "_d21"))
  if (nrow(m) <= 5) return(list(pass = FALSE, note = "insufficient serum-VitD data"))
  m$chg <- m$VITD_d21 - m$VITD_scrn; m <- merge(m, dm, by = "USUBJID")
  ch <- tapply(m$chg, m$ARMCD, mean); vd <- ch[["VITD"]] %||% NA; pbo <- ch[["PBO"]] %||% NA
  list(serumD_change_VITD = round(vd, 2), serumD_change_PBO = round(pbo, 2), gap = round(vd - pbo, 2), pass = isTRUE(vd - pbo > min_gap))
}

# ---- causal: stratifier direction (baseline IgE is higher in AD than NonAD) ----
cath_gate_stratifier_sign <- function(crfs) {
  lb <- .cath_gload(crfs, "LB"); dm <- .cath_gload(crfs, "DM")[, c("USUBJID", "DIAGGRP")]
  scrn <- merge(lb[lb$VISIT == "SCRN", c("USUBJID", "IGE")], dm, by = "USUBJID")
  ige <- tapply(scrn$IGE, scrn$DIAGGRP, mean); ad <- ige[["AD"]] %||% NA; nonad <- ige[["NonAD"]] %||% NA
  list(ige_AD = round(ad, 1), ige_NonAD = round(nonad, 1), pass = isTRUE(ad > nonad))
}

# ---- invariant #4: shared f_amp frailty not zeroed (biopsy CAMP and tape-strip CAMP move together) ----
cath_gate_frailty_cluster <- function(crfs, min_r = 0.2) {
  bx <- .cath_gload(crfs, "BX"); ts <- .cath_gload(crfs, "TS")
  b <- bx[bx$VISIT == "BL", c("USUBJID", "CAMP_NONLES")]; t <- ts[ts$VISIT == "BL", c("USUBJID", "TS_CAMP_NONLES")]
  m <- merge(b, t, by = "USUBJID")
  if (nrow(m) <= 5) return(list(r_biopsy_tapestrip_camp = NA, n = nrow(m), pass = FALSE))
  r <- cor(m$CAMP_NONLES, m$TS_CAMP_NONLES)
  list(r_biopsy_tapestrip_camp = round(r, 3), n = nrow(m), pass = isTRUE(r > min_r))
}

cath_run_dag_gates <- function(crfs) {
  gates <- list(
    g_visit_date_variance        = cath_gate_visit_date_variance(crfs),
    g_ae_onset_dispersion        = cath_gate_ae_onset_dispersion(crfs),
    g_discontinuation_continuous = cath_gate_discontinuation_continuous(crfs),
    g_ae_ds_traceability         = cath_gate_ae_ds_traceability(crfs),
    g_endpoint_derived_from_trajectory = cath_gate_endpoint_derived(crfs),
    g_arm_mediator_direction     = cath_gate_arm_mediator(crfs),
    g_stratifier_sign            = cath_gate_stratifier_sign(crfs),
    g_frailty_cluster_corr       = cath_gate_frailty_cluster(crfs),
    g_logical_consistency        = gate_logical_consistency(crfs, "CATH", CATH_APPLICABILITY_RULES, CATH_CONSISTENCY_RULES)
  )
  gates$all_pass <- all(vapply(gates, function(g) isTRUE(g$pass), logical(1)))
  gates
}

# diagnostic: re-run the gates that are under-powered at N=82 (#182/#184) on a larger cohort
cath_run_high_n_confirmation <- function(crfs) list(
  crfs_dir = crfs,
  g_ae_onset_dispersion = cath_gate_ae_onset_dispersion(crfs),
  g_ae_ds_traceability = cath_gate_ae_ds_traceability(crfs))
