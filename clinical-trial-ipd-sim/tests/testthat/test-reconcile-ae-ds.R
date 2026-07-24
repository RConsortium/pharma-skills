# reconcile_ae_ds (#184): keeps the AE and DS records in agreement, including the zero-serious-AE case (like CATH).
mk_patient <- function(reason, aes) {
  ct_rec(discontinuation_reason = reason, discontinuation_visit_day = 10L,
         trajectory = list(ct_rec(visit_day = 10L, actual_day = 10L, aes = aes)))
}

test_that("an AE-driven exit keeps exactly one DRUG WITHDRAWN (latest), demotes the rest", {
  aes <- list(ct_rec(AEACN = "DRUG WITHDRAWN", AESER = "N", AEDY = 5L),
              ct_rec(AEACN = "DRUG WITHDRAWN", AESER = "N", AEDY = 8L))
  p <- mk_patient("ADVERSE EVENT", aes)
  StubSim$new()$reconcile_ae_ds(p)
  acns <- vapply(p$trajectory[[1]]$aes, function(a) a$AEACN, character(1))
  expect_equal(sum(acns == "DRUG WITHDRAWN"), 1L)
  expect_equal(p$trajectory[[1]]$aes[[2]]$AEACN, "DRUG WITHDRAWN")   # the latest (AEDY=8) is the trigger
  expect_equal(p$trajectory[[1]]$aes[[1]]$AEACN, "DRUG INTERRUPTED")
})

test_that("a non-AE exit demotes every withdrawn AE", {
  aes <- list(ct_rec(AEACN = "DRUG WITHDRAWN", AESER = "N", AEDY = 5L))
  p <- mk_patient("WITHDRAWAL BY SUBJECT", aes)
  StubSim$new()$reconcile_ae_ds(p)
  expect_equal(p$trajectory[[1]]$aes[[1]]$AEACN, "DRUG INTERRUPTED")
})
