run_cath_once <- function(dir) {
  unlink(dir, recursive = TRUE)
  CathSim$new()$run(out_dir = dir, verify = TRUE, render_html = FALSE, manifest = FALSE)
  dir
}

test_that("CATH runs, emits 17 forms, and passes all 8 DAG gates", {
  out <- run_cath_once(file.path(tempdir(), "cath_test"))
  expect_length(list.files(file.path(out, "crfs")), 17)
  g <- cath_run_dag_gates(file.path(out, "crfs"))
  expect_true(isTRUE(g$all_pass))
})

test_that("EX is emitted for every subject (fix #1) and dropouts carry no Day-21 data (fix #2)", {
  out <- run_cath_once(file.path(tempdir(), "cath_fixes"))
  dm <- readr::read_csv(file.path(out, "crfs", "CATH_CRF_DM.csv"), show_col_types = FALSE)
  ex <- readr::read_csv(file.path(out, "crfs", "CATH_CRF_EX.csv"), show_col_types = FALSE)
  expect_equal(nrow(ex), nrow(dm))                          # EX for ALL, not one diagnosis group
  ds <- readr::read_csv(file.path(out, "crfs", "CATH_CRF_DS.csv"), show_col_types = FALSE)
  bx <- readr::read_csv(file.path(out, "crfs", "CATH_CRF_BX.csv"), show_col_types = FALSE)
  disc <- ds$USUBJID[ds$DSDECOD != "COMPLETED"]
  expect_gt(length(disc), 0)                                # there ARE dropouts
  expect_equal(sum(bx$VISIT == "D21" & bx$USUBJID %in% disc), 0)  # none carry a Day-21 biopsy
})

test_that("CATH has zero serious AEs by design (FDA grade 4 never produced)", {
  out <- run_cath_once(file.path(tempdir(), "cath_sae"))
  m <- cath_compute_marginals(file.path(out, "crfs"))
  expect_equal(m$ae_serious_count, 0)
})
