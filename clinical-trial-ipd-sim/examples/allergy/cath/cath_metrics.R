# CATH Step-6 marginals + comparison against targets. Ported from causal_examples/allergy/cath/metrics.py.
# compute_marginals reads the EMITTED CSVs; build_targets reads the published results (Step-4 snapshot
# targets plus posted baseline/AE/flow); compare uses the tolerance model from calibration.md
# (mean within 95% CI half-width, proportion within a normal-approx band, SD within +/-50%, counts +/-2).

cath_load_crfs <- function(crfs) {
  out <- list()
  for (f in list.files(crfs, pattern = "^CATH_CRF_.*\\.csv$", full.names = TRUE))
    out[[sub("\\.csv$", "", sub("^CATH_CRF_", "", basename(f)))]] <- readr::read_csv(f, show_col_types = FALSE, progress = FALSE)
  out
}

cath_compute_marginals <- function(crfs) {
  d <- cath_load_crfs(crfs); dm <- d$DM; lb <- d$LB; bx <- d$BX; sk <- d$SK; ds <- d$DS; ae <- d$AE
  N <- length(unique(dm$USUBJID)); m <- list(N = N)

  grp <- table(dm$DIAGGRP)
  m$group_counts <- setNames(lapply(c("NonAD", "AD", "Psor"), function(g) as.integer(grp[g] %||% 0)), c("NonAD", "AD", "Psor"))
  m$p_female <- mean(dm$SEX == "F")
  m$race_props <- setNames(lapply(c("White", "Asian", "Black", "Other"), function(r) mean(dm$RACE == r)), c("White", "Asian", "Black", "Other"))
  m$p_hispanic <- mean(dm$ETHNIC == "HISPANIC OR LATINO"); m$p_usa <- mean(dm$COUNTRY == "USA")
  m$age_mean <- mean(dm$AGE); m$age_sd <- sd(dm$AGE); m$bmi_mean <- mean(dm$BMI); m$bmi_sd <- sd(dm$BMI)

  scrn <- lb[lb$VISIT == "SCRN", ]
  for (ck in list(c("VITD", "vitd"), c("CREAT", "creat"), c("PTH", "pth"), c("CALCIUM", "calcium"), c("IGE", "ige"))) {
    m[[paste0(ck[2], "_mean")]] <- mean(scrn[[ck[1]]]); m[[paste0(ck[2], "_sd")]] <- sd(scrn[[ck[1]]])
  }
  skbl <- sk[sk$VISIT == "BL", ]; fz <- prop.table(table(skbl$FITZPATRICK))
  m$fitz_props <- as.list(fz)

  arm <- setNames(dm$ARMCD, dm$USUBJID); dgrp <- setNames(dm$DIAGGRP, dm$USUBJID)
  endpoints <- list()
  for (bmk in list(c("camp", "CAMP"), c("hbd3", "HBD3"), c("il13", "IL13"))) {
    bm <- bmk[1]; stem <- bmk[2]; endpoints[[bm]] <- list()
    for (cs in list(c("lesional", "LES"), c("nonlesional", "NONLES"))) {
      comp <- cs[1]; col <- paste0(stem, "_", cs[2])
      bl <- bx[bx$VISIT == "BL", c("USUBJID", col)]; d21 <- bx[bx$VISIT == "D21", c("USUBJID", col)]
      if (!nrow(bl) || !nrow(d21)) next
      mm <- merge(bl, d21, by = "USUBJID", suffixes = c("_bl", "_d21"))
      mm$chg <- mm[[paste0(col, "_d21")]] - mm[[paste0(col, "_bl")]]
      mm$grp <- dgrp[mm$USUBJID]; mm$arm <- arm[mm$USUBJID]
      for (g in c("NonAD", "AD", "Psor")) for (ak in list(c("VITD", "vitd"), c("PBO", "placebo"))) {
        sub <- mm$chg[mm$grp == g & mm$arm == ak[1]]
        sub <- sub[!is.na(sub)]           # skip cells with no data (e.g. lesional fields in a no-lesion group)
        if (!length(sub)) next
        if (is.null(endpoints[[bm]][[g]])) endpoints[[bm]][[g]] <- list()
        if (is.null(endpoints[[bm]][[g]][[comp]])) endpoints[[bm]][[g]][[comp]] <- list()
        endpoints[[bm]][[g]][[comp]][[ak[2]]] <- list(mean = round(mean(sub), 3), sd = round(sd(sub), 3), n = length(sub))
      }
    }
  }
  m$endpoints <- endpoints

  ae_subj <- unique(ae$USUBJID)
  m$ae_any_rate <- round(length(ae_subj) / N, 4)
  m$ae_serious_count <- sum(toupper(as.character(ae$AESER)) == "Y")
  if (nrow(ae)) {
    pt_inc <- tapply(ae$USUBJID, ae$AEDECOD, function(u) length(unique(u)) / N)
    m$ae_max_pt_incidence <- round(max(pt_inc), 4); m$ae_pt_incidence <- as.list(round(pt_inc, 4))
  } else { m$ae_max_pt_incidence <- 0.0; m$ae_pt_incidence <- list() }

  completed <- sum(ds$DSDECOD == "COMPLETED")
  m$n_completed <- completed; m$n_not_completed <- N - completed
  disc <- ds$DSTERM[ds$DSDECOD != "COMPLETED"]
  m$disc_reasons <- as.list(table(disc))
  m
}

cath_build_targets <- function(path = NULL) {
  if (is.null(path)) path <- skill_file("examples", "allergy", "cath", "params", "params_final.json")
  pcal <- jsonlite::fromJSON(paste(readLines(path, warn = FALSE), collapse = "\n"), simplifyDataFrame = FALSE)$params$Lt_endpoint_substrate_CALIBRATED
  endp <- list()
  for (bk in list(c("camp", "camp_change"), c("hbd3", "hbd3_change"), c("il13", "il13_change"))) {
    bm <- bk[1]; endp[[bm]] <- list()
    for (g in names(pcal[[bk[2]]])) for (comp in names(pcal[[bk[2]]][[g]])) {
      t <- pcal[[bk[2]]][[g]][[comp]]$target
      if (is.null(endp[[bm]][[g]])) endp[[bm]][[g]] <- list()
      endp[[bm]][[g]][[comp]] <- list(vitd_mean = t$vitd_mean, vitd_sd = t$vitd_sd, placebo_mean = t$placebo_mean, placebo_sd = t$placebo_sd)
    }
  }
  list(
    baseline = list(
      group_counts = list(NonAD = 32, AD = 34, Psor = 16), p_female = 44/82, p_hispanic = 9/82, p_usa = 82/82,
      race_props = list(White = 54/82, Asian = 10/82, Black = 9/82, Other = 9/82),
      age_mean = 32.5, age_sd = 10.9, bmi_mean = 25.3, bmi_sd = 4.9,
      vitd_mean = 29.2, vitd_sd = 11.2, creat_mean = 0.8, creat_sd = 0.2,
      pth_mean = 34.4, pth_sd = 11.4, calcium_mean = 9.4, calcium_sd = 0.4, ige_mean = 553.3, ige_sd = 1825.2),
    endpoints = endp,
    ae = list(any_ge_5pct = 0, serious = 0),
    flow = list(n_completed = 76, n_not_completed = 6,
                disc_reasons = list(`WITHDRAWAL BY SUBJECT` = 3, `PROTOCOL VIOLATION` = 2, `ADVERSE EVENT` = 1)))
}

.mean_tol <- function(sd, n) 1.96 * sd / sqrt(max(n, 1))
.prop_tol <- function(p, N) 1.96 * sqrt(max(p * (1 - p), 1e-6) / N)

cath_compare <- function(marg, targets) {
  N <- marg$N; rows <- list()
  add <- function(name, tgt, sim, ok, kind) rows[[length(rows) + 1L]] <<- list(
    metric = name, target = if (is.null(tgt)) NA else round(as.numeric(tgt), 4),
    sim = if (is.null(sim)) NA else round(as.numeric(sim), 4), within_tol = isTRUE(ok), kind = kind)
  b <- marg; tb <- targets$baseline
  for (g in c("NonAD", "AD", "Psor")) {
    p_t <- tb$group_counts[[g]] / 82; p_s <- b$group_counts[[g]] / N
    add(sprintf("group_prop[%s]", g), p_t, p_s, abs(p_s - p_t) <= .prop_tol(p_t, N), "prop")
  }
  add("p_female", tb$p_female, b$p_female, abs(b$p_female - tb$p_female) <= .prop_tol(tb$p_female, N), "prop")
  add("p_hispanic", tb$p_hispanic, b$p_hispanic, abs(b$p_hispanic - tb$p_hispanic) <= .prop_tol(tb$p_hispanic, N), "prop")
  add("p_usa", tb$p_usa, b$p_usa, abs(b$p_usa - tb$p_usa) <= 0.001, "prop")
  for (r in c("White", "Asian", "Black", "Other"))
    add(sprintf("race_prop[%s]", r), tb$race_props[[r]], b$race_props[[r]], abs(b$race_props[[r]] - tb$race_props[[r]]) <= .prop_tol(tb$race_props[[r]], N), "prop")
  for (key in c("age", "bmi", "vitd", "creat", "pth", "calcium")) {
    tgt <- tb[[paste0(key, "_mean")]]; sd <- tb[[paste0(key, "_sd")]]
    add(paste0(key, "_mean"), tgt, b[[paste0(key, "_mean")]], abs(b[[paste0(key, "_mean")]] - tgt) <= .mean_tol(sd, N), "mean")
  }
  add("ige_mean", tb$ige_mean, b$ige_mean, { r <- b$ige_mean / tb$ige_mean; 0.5 <= r && r <= 2.0 }, "mean_skewed")

  for (bm in c("camp", "hbd3", "il13")) for (g in names(targets$endpoints[[bm]])) for (comp in names(targets$endpoints[[bm]][[g]])) {
    t <- targets$endpoints[[bm]][[g]][[comp]]
    sim <- tryCatch(marg$endpoints[[bm]][[g]][[comp]], error = function(e) NULL)
    for (ak in list(c("vitd", "vitd_mean", "vitd_sd"), c("placebo", "placebo_mean", "placebo_sd"))) {
      s <- if (!is.null(sim)) sim[[ak[1]]] else NULL
      if (is.null(s)) { add(sprintf("%s[%s/%s/%s].mean", bm, g, comp, ak[1]), t[[ak[2]]], NULL, FALSE, "mean"); next }
      add(sprintf("%s[%s/%s/%s].mean", bm, g, comp, ak[1]), t[[ak[2]]], s$mean, abs(s$mean - t[[ak[2]]]) <= .mean_tol(t[[ak[3]]], s$n), "mean")
      add(sprintf("%s[%s/%s/%s].sd", bm, g, comp, ak[1]), t[[ak[3]]], s$sd, abs(s$sd - t[[ak[3]]]) <= 0.5 * t[[ak[3]]], "sd")
    }
  }
  add("ae_serious_count", targets$ae$serious, marg$ae_serious_count, marg$ae_serious_count == 0, "count")
  add("ae_max_PT_incidence(<5%)", 0.05, marg$ae_max_pt_incidence, marg$ae_max_pt_incidence < 0.05, "threshold")
  tf <- targets$flow
  add("n_not_completed", tf$n_not_completed, marg$n_not_completed, abs(marg$n_not_completed - tf$n_not_completed) <= 2, "count")
  for (reason in names(tf$disc_reasons)) {
    sv <- marg$disc_reasons[[reason]] %||% 0
    add(sprintf("disc[%s]", reason), tf$disc_reasons[[reason]], sv, abs(as.numeric(sv) - tf$disc_reasons[[reason]]) <= 2, "count")
  }
  n_ok <- sum(vapply(rows, function(r) isTRUE(r$within_tol), logical(1)))
  list(rows = rows, n_metrics = length(rows), n_within_tol = n_ok, all_within_tol = (n_ok == length(rows)))
}
