# Logical-consistency layer: enforce_applicability() blanks fields that don't apply to a subject, and
# gate_logical_consistency() re-checks it and fails if anything is off. Neither is tied to a specific
# trial, so a tiny made-up dataset can test them without a full run.

test_that("enforce_applicability blanks non-applicable fields, keeps applicable ones", {
  Sub <- R6::R6Class("Sub", inherit = TrialSim, public = list(
    applicability_rules = function() list(
      list(form = "BX", cols = "CAMP_LES",
           applicable = function(dm) dm$DIAGGRP %in% c("Psor", "AD"), label = "lesional needs a lesion"))))
  frames <- list(
    DM = tibble::tibble(USUBJID = c("a", "b", "c"), DIAGGRP = c("Psor", "AD", "NonAD")),
    BX = tibble::tibble(USUBJID = c("a", "b", "c"), CAMP_LES = c(3.1, 2.0, 4.2), CAMP_NONLES = c(1, 1, 1)))
  out <- Sub$new()$enforce_applicability(frames)
  expect_equal(out$BX$CAMP_LES[1:2], c(3.1, 2.0))   # lesion-bearing groups kept
  expect_true(is.na(out$BX$CAMP_LES[3]))            # no-lesion control blanked
  expect_equal(out$BX$CAMP_NONLES, c(1, 1, 1))      # column with no rule left alone
})

# helper: write a minimal CRF bundle to a fresh temp dir and return it
.write_bundle <- function(dm, bx = NULL, pt = NULL) {
  dir <- tempfile("lc_crfs_"); dir.create(dir)
  readr::write_csv(dm, file.path(dir, "CATH_CRF_DM.csv"), na = "")
  if (!is.null(bx)) readr::write_csv(bx, file.path(dir, "CATH_CRF_BX.csv"), na = "")
  if (!is.null(pt)) readr::write_csv(pt, file.path(dir, "CATH_CRF_PT.csv"), na = "")
  dir
}

APP <- list(list(form = "BX", cols = "CAMP_LES",
                 applicable = function(dm) dm$DIAGGRP %in% c("Psor", "AD"), label = "lesional needs a lesion"))
CON <- list(list(form = "PT", ok = function(r) r$SEX == "F", label = "pregnancy only for females"),
            list(form = "DM", ok = function(r) r$AGE >= 18 & r$AGE <= 70, label = "age in eligibility"))

test_that("gate passes clean data", {
  dm <- tibble::tibble(USUBJID = c("a", "b", "c"), DIAGGRP = c("Psor", "AD", "NonAD"),
                       SEX = c("F", "M", "F"), AGE = c(40, 55, 30))
  bx <- tibble::tibble(USUBJID = c("a", "b", "c"), CAMP_LES = c(3.1, 2.0, NA))   # control blank
  pt <- tibble::tibble(USUBJID = c("a", "c"))                                    # SEX comes from the DM join
  g <- gate_logical_consistency(.write_bundle(dm, bx, pt), "CATH", APP, CON)
  expect_true(g$pass); expect_equal(g$violations, 0)
})

test_that("gate fails on a value where the measurement can't exist", {
  dm <- tibble::tibble(USUBJID = c("a", "c"), DIAGGRP = c("Psor", "NonAD"), SEX = c("F", "F"), AGE = c(40, 30))
  bx <- tibble::tibble(USUBJID = c("a", "c"), CAMP_LES = c(3.1, 4.2))   # NonAD has a lesional value it can't have (EP-01)
  g <- gate_logical_consistency(.write_bundle(dm, bx), "CATH", APP, list())
  expect_false(g$pass)
  expect_equal(g$detail[["lesional needs a lesion"]]$value_where_inapplicable, 1)
})

test_that("gate fails on a blank where the measurement should exist", {
  dm <- tibble::tibble(USUBJID = c("a", "c"), DIAGGRP = c("Psor", "NonAD"), SEX = c("F", "F"), AGE = c(40, 30))
  bx <- tibble::tibble(USUBJID = c("a", "c"), CAMP_LES = c(NA, NA))     # Psor lesional missing
  g <- gate_logical_consistency(.write_bundle(dm, bx), "CATH", APP, list())
  expect_false(g$pass)
  expect_equal(g$detail[["lesional needs a lesion"]]$blank_where_applicable, 1)
})

test_that("gate fails on an impossible demographic combination (male pregnancy record, out-of-range age)", {
  dm <- tibble::tibble(USUBJID = c("a", "b"), DIAGGRP = c("Psor", "AD"), SEX = c("F", "M"), AGE = c(40, 80))
  pt <- tibble::tibble(USUBJID = c("a", "b"))                          # subject b (male) has a pregnancy row
  g <- gate_logical_consistency(.write_bundle(dm, bx = NULL, pt = pt), "CATH", list(), CON)
  expect_false(g$pass)
  expect_equal(g$detail[["pregnancy only for females"]]$violations, 1)  # the male PT row
  expect_equal(g$detail[["age in eligibility"]]$violations, 1)          # the age-80 subject
})
