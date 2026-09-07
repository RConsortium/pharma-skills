#!/usr/bin/env Rscript
# Scan an R source tree for the rounding function catalog.
# Usage: Rscript scan-rounding-calls.R <dir>
# Base R only. Prints the file inventory plus every catalog match as
# <relpath>:<line>: <expression> [patterns]. Exit nonzero on bad input.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || !dir.exists(args[1L])) {
  cat("usage: Rscript scan-rounding-calls.R <dir>\n")
  quit(status = 1L)
}
root <- normalizePath(args[1L])
files <- sort(list.files(root, pattern = "[.]R$", recursive = TRUE,
  full.names = TRUE))
cat(sprintf("root: %s\n", root))
cat(sprintf("r_files: %d\n", length(files)))
for (f in files) {
  cat(sprintf("  file: %s\n", sub(paste0("^", root, "/?"), "", f)))
}
cat("r_version:", R.version.string, "\n")

catalog <- c("round\\(", "signif\\(", "round5\\(", "roundSAS\\(",
  "round_half_up\\(", "round_up\\(", "ceiling\\(", "floor\\(", "trunc\\(",
  "formatC\\(", "sprintf\\(", "format\\(", "prettyNum\\(",
  "as\\.character\\(", "paste0\\(")
total <- 0L
for (f in files) {
  lines <- suppressWarnings(readLines(f, warn = FALSE))
  rel <- sub(paste0("^", root, "/?"), "", f)
  for (i in seq_along(lines)) {
    hits <- catalog[vapply(catalog, function(p) grepl(p, lines[i]),
      logical(1L))]
    if (length(hits)) {
      total <- total + 1L
      cat(sprintf("%s:%d: %s  [%s]\n", rel, i,
        trimws(substr(lines[i], 1L, 120L)), paste(hits, collapse = ",")))
    }
  }
}
cat(sprintf("catalog_matches: %d\n", total))
cat("note: FIRST PASS ONLY -- a file with no matches is not cleared. Infer wrappers, custom helpers, methods, and indirect numeric-to-text paths, and record them as exploratory.\n")
