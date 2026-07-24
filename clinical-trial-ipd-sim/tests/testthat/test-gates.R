# Run the shared realism gates (R/gates.R) against the CSVs a RAVE run emits.
test_that("run_realism_gates passes on a RAVE run (adapted gate_config)", {
  out <- file.path(tempdir(), "rave_realism"); unlink(out, recursive = TRUE)
  RaveSim$new()$run(out_dir = out, verify = TRUE, render_html = FALSE, manifest = FALSE)
  nominal_by_visit <- setNames(lapply(RAVE_SCHED, function(s) s$day), vapply(RAVE_SCHED, function(s) s$key, ""))
  cfg <- gate_config(
    crfs_dir = file.path(out, "crfs"), prefix = "RAVE",
    nominal_days = vapply(RAVE_SCHED, function(s) s$day, integer(1)),
    visit_form = "LB_HEM", visit_day_col = "LBDY",
    ds_day_col = "DSSTDY", nominal_by_visit = nominal_by_visit)
  g <- run_realism_gates(cfg)
  expect_true(isTRUE(g$g_visit_date_variance$pass))     # #183a
  expect_true(isTRUE(g$g_ae_onset_dispersion$pass))     # #182
  expect_true(isTRUE(g$g_ae_ds_traceability$pass))      # #184
  expect_true(isTRUE(g$all_pass))
})
