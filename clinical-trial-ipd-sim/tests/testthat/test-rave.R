test_that("RAVE runs, emits 12 forms, passes all 6 DAG gates, and reproduces (seed)", {
  out <- file.path(tempdir(), "rave_test"); unlink(out, recursive = TRUE)
  res <- RaveSim$new()$run(out_dir = out, verify = TRUE, render_html = FALSE, manifest = FALSE)
  expect_length(res$files, 12)
  expect_true(isTRUE(res$gates$all_pass))
  # reproducible: same seed -> identical DM
  out2 <- file.path(tempdir(), "rave_test2"); unlink(out2, recursive = TRUE)
  RaveSim$new()$run(out_dir = out2, verify = FALSE, render_html = FALSE, manifest = FALSE)
  dm1 <- readr::read_csv(file.path(out, "crfs", "RAVE_CRF_DM.csv"), show_col_types = FALSE)
  dm2 <- readr::read_csv(file.path(out2, "crfs", "RAVE_CRF_DM.csv"), show_col_types = FALSE)
  expect_equal(dm1, dm2)
})

test_that("RAVE calibrated primary endpoint lands within TOL", {
  out <- file.path(tempdir(), "rave_marg"); unlink(out, recursive = TRUE)
  RaveSim$new()$run(out_dir = out, verify = TRUE, render_html = FALSE, manifest = FALSE)
  m <- rave_compute_marginals(file.path(out, "crfs"))
  expect_lt(abs(m$cr6mo_RTX - RAVE_TARGETS$cr6mo_RTX), RAVE_TOL)
  expect_lt(abs(m$cr6mo_CYC - RAVE_TARGETS$cr6mo_CYC), RAVE_TOL)
})

test_that("RAVE endpoints are derived from the trajectory (g4 agreement ~1)", {
  out <- file.path(tempdir(), "rave_g4"); unlink(out, recursive = TRUE)
  RaveSim$new()$run(out_dir = out, verify = TRUE, render_html = FALSE, manifest = FALSE)
  g <- rave_run_dag_gates(file.path(out, "crfs"))
  expect_gt(g$g4_endpoint_is_trajectory$agreement, 0.98)
})
