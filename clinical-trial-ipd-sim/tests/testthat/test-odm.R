# ODM tests that shell out to python3 — they skip unless a python3 with the needed packages is set up (PY_OK from setup.R).

test_that("RAVE emitted columns match the crf_picks.json contract (both directions)", {
  skip_if_not(PY_OK, "no python3 with lxml+duckdb configured")
  out <- file.path(tempdir(), "rave_odm_c"); unlink(out, recursive = TRUE)
  RaveSim$new()$run(out_dir = out, verify = FALSE, render_html = FALSE, manifest = FALSE)
  picks <- skill_file("examples", "autoimmune", "rave", "odm", "crf_picks.json")
  expect_true(odm_check_columns(picks, file.path(out, "crfs")))
})

test_that("RAVE ODM v2.0 blank form + filled export both validate", {
  skip_if_not(PY_OK, "no python3 with lxml+duckdb configured")
  out <- file.path(tempdir(), "rave_odm_r"); unlink(out, recursive = TRUE)
  RaveSim$new()$run(out_dir = out, verify = FALSE, render_html = FALSE, manifest = FALSE)
  picks <- skill_file("examples", "autoimmune", "rave", "odm", "crf_picks.json")
  tpl <- odm_build_template(picks, out)                    # build_spec -> emit_odm -> check_odm (stops if the check fails)
  expect_true(file.exists(tpl))
  xml <- odm_fill(tpl, file.path(out, "crfs"), file.path(out, "odm", "odm.xml"))
  expect_true(file.exists(xml))
})

test_that("CATH emitted columns match its crf_picks.json contract", {
  skip_if_not(PY_OK, "no python3 with lxml+duckdb configured")
  out <- file.path(tempdir(), "cath_odm_c"); unlink(out, recursive = TRUE)
  CathSim$new()$run(out_dir = out, verify = FALSE, render_html = FALSE, manifest = FALSE)
  picks <- skill_file("examples", "allergy", "cath", "odm", "crf_picks.json")
  expect_true(odm_check_columns(picks, file.path(out, "crfs")))
})
