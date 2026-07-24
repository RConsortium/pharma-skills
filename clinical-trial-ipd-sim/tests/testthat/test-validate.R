test_that("validate_config rejects a bad config and passes a good one", {
  good <- StubSim$new()
  expect_silent(validate_config(good))
  bad <- StubSim$new(); bad$admin_censor_day <- -1
  expect_error(validate_config(bad), "admin_censor_day")
})

test_that("validate_params is the extra='forbid' typo net and returns the input unchanged", {
  p <- list(a = 1, b = 2)
  expect_identical(validate_params(p, allowed = c("a", "b")), p)
  expect_error(validate_params(list(a = 1, zzz = 9), allowed = c("a", "b")), "unknown params")
})

test_that("constrained-type asserts fire on out-of-range values", {
  expect_error(assert_prob(1.5), "probability")
  expect_error(assert_pos(0), "> 0")
  expect_silent(assert_prob(0.5))
})

test_that("RAVE default params validate and round-trip", {
  p <- rave_default_params()
  expect_true(is.list(p) && length(p) > 40)
  expect_identical(validate_params(p, names(RAVE_DEFAULT_PARAMS), RAVE_PARAM_CHECKS), p)
})
