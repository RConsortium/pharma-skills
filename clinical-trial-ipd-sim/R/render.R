# Step 8 — render the finished trial to a browser page. Shells out to the VENDORED Python renderer
# (render_trial_docs.py), which parses DAG.md/CRF_spec.md/README.md and writes <out_dir>/index.html
# (the deliverable) plus a best-effort secondary docs copy.
#
# BEST-EFFORT: a missing DAG.md, a missing python, or a render error just prints a note and returns
# FALSE — it NEVER breaks the simulation. index.html is the only artifact we rely on.
render_docs <- function(out_dir) {
  ok <- tryCatch({
    if (!file.exists(file.path(out_dir, "DAG.md"))) {
      message("ctids render: no DAG.md in ", out_dir, " -> skipping HTML render")
      return(FALSE)
    }
    py     <- skill_python()
    script <- skill_file("vendor", "python", "render", "render_trial_docs.py")
    status <- system2(py, c(shQuote(script), shQuote(out_dir)), stdout = "", stderr = "")
    if (!identical(as.integer(status), 0L)) {
      message("ctids render: renderer exited ", status, " -> HTML skipped (non-fatal)")
      return(FALSE)
    }
    file.exists(file.path(out_dir, "index.html"))
  }, error = function(e) {
    message("ctids render: ", conditionMessage(e), " -> HTML skipped (non-fatal)")
    FALSE
  })
  invisible(ok)
}
