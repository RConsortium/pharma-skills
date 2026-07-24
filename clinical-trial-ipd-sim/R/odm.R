# ODM step — thin R wrappers that shell out to the VENDORED Python toolchain (unchanged).
#
# Locked design: the whole CDISC ODM v2.0 chain stays Python (lxml XML + duckdb CDE index + XSD
# validation); R only (a) authors crf_picks.json and (b) emits the CSVs, then calls these wrappers.
# The scripts live under <skill>/vendor/python/odm/ and self-locate the duckdb index and xsd_v2/
# schemas by relative path, so they need no path arguments and no edits.
#
# Fail-closed: a non-zero Python exit raises in R (base system2, no extra deps).

# Run a vendored python script; fail closed on non-zero exit. Streams the script's own output.
.odm_py <- function(script, args = character(0)) {
  py     <- skill_python()
  script <- skill_file("vendor", "python", "odm", script)
  status <- system2(py, c(shQuote(script), shQuote(args)), stdout = "", stderr = "")
  if (!identical(as.integer(status), 0L))
    stop(sprintf("ctids ODM: %s exited %s (fail-closed)", basename(script), status), call. = FALSE)
  invisible(0L)
}

# Step-2 picker aid: BM25 search of the NCI CDE index. Returns the printed candidate lines.
nci_search <- function(query, k = 5L) {
  py     <- skill_python()
  script <- skill_file("vendor", "python", "odm", "search_nci.py")
  system2(py, c(shQuote(script), shQuote(query), shQuote(as.character(k))), stdout = TRUE, stderr = TRUE)
}

# Step 2 — build + validate the BLANK ODM form from crf_picks.json.
# Writes <out_dir>/odm/crf_spec.json and <out_dir>/odm/crf_template.xml; check_odm gates 1+2.
# Returns the template path.
odm_build_template <- function(picks_path, out_dir) {
  odm_dir <- file.path(out_dir, "odm")
  dir.create(odm_dir, recursive = TRUE, showWarnings = FALSE)
  spec     <- file.path(odm_dir, "crf_spec.json")
  template <- file.path(odm_dir, "crf_template.xml")
  .odm_py("build_spec.py", c(picks_path, spec))
  .odm_py("emit_odm.py",   c(spec, template))
  .odm_py("check_odm.py",  template)                       # Gate 1 (XSD) + Gate 2 (refs) — fail-closed
  invisible(template)
}

# Step 5 — contract check: emitted CSV columns match crf_picks.json BOTH ways. Fail-closed on drift.
odm_check_columns <- function(picks_path, crfs_dir) {
  .odm_py("check_columns.py", c(picks_path, crfs_dir))
  invisible(TRUE)
}

# Step 7 — fill the blank template with the emitted CSVs, then re-validate. Returns the odm.xml path.
odm_fill <- function(template_path, crfs_dir, out_xml) {
  dir.create(dirname(out_xml), recursive = TRUE, showWarnings = FALSE)
  .odm_py("emit_clinicaldata.py", c(template_path, crfs_dir, out_xml))
  .odm_py("check_odm.py",         out_xml)                 # release gate — fail-closed
  invisible(out_xml)
}
