# Y — derives the CATH endpoints from the trajectory. Ported from cath_outcomes.py.
# Every endpoint is a change-from-baseline of an Lt node (delta = D21 - baseline), READ OFF the
# trajectory, never drawn. Dropouts (no D21) have no delta. reconcile_ae_ds runs centrally in
# the engine's simulate_one, not here.

.cath_delta <- function(d21, bl, key) {
  if (is.null(d21) || is.null(bl)) return(NULL)
  a <- d21$data[[key]]; b <- bl$data[[key]]
  if (is.null(a) || is.null(b) || identical(a, "") || identical(b, "")) return(NULL)
  round(as.numeric(a) - as.numeric(b), 3)
}

cath_derive_endpoints <- function(sim, patient) {
  bl <- cath_row(patient, "BL"); d21 <- cath_row(patient, "D21")
  if (!is.null(d21) && !is.null(bl)) {
    for (bm in c("CAMP", "HBD3", "IL13", "IL4")) {
      for (comp in c("LES", "NONLES")) {
        k <- paste0(bm, "_", comp)
        patient$deltas[[paste0("d_", k)]] <- .cath_delta(d21, bl, k)
      }
      dl <- patient$deltas[[paste0("d_", bm, "_LES")]]; dn <- patient$deltas[[paste0("d_", bm, "_NONLES")]]
      patient$deltas[[paste0("contrast_", bm)]] <- if (!is.null(dl) && !is.null(dn)) round(dl - dn, 3) else NULL
    }
    patient$deltas$d_CFU_LES <- .cath_delta(d21, bl, "CFU_LES")
    patient$deltas$d_CFU_NONLES <- .cath_delta(d21, bl, "CFU_NONLES")
    patient$deltas$d_PASI <- .cath_delta(d21, bl, "PASI")
  }
  if (patient$not_completed) {
    patient$disposition <- "DISCONTINUED"
    patient$last_contact_day <- patient$discontinuation_day %||% patient$discontinuation_visit_day %||% 0L
  } else {
    patient$disposition <- "COMPLETED"; patient$discontinuation_reason <- NULL
    patient$last_contact_day <- if (!is.null(d21)) d21$actual_day else 21L
  }
  invisible(patient)
}
