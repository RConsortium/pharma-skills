test_that("calibration_report simulates fail-closed and returns marginals + comparison", {
  rep <- calibration_report(RaveSim$new())
  expect_true(is.list(rep$marginals))
  expect_true(!is.null(rep$marginals$cr6mo_RTX))
})

test_that("calibrate() runs a params-only loop, stays fail-closed, and reports a status", {
  # a simple one-knob loop: nudge remit_intercept toward a slightly higher CR6MO target.
  sim <- RaveSim$new()
  res <- calibrate(sim,
    targets  = list(cr6mo_RTX = 0.65),
    knob_map = list(cr6mo_RTX = list(knob = "remit_intercept", dir = 1, step = 0.1, min = -2, max = 3)),
    scales   = list(cr6mo_RTX = 0.07), max_iter = 2L, tol = 0.02)
  expect_true(res$status %in% c("SUCCESS", "STALLED"))
  expect_true(is.numeric(res$err) && is.finite(res$err))
})
