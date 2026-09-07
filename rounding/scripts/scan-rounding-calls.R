#!/usr/bin/env Rscript
# Inventory the rounding-relevant call sites in an R source tree.
#
# Usage: Rscript scan-rounding-calls.R <dir> [--include-tests]
#
# Base R only. Unlike a text grep, this walks R's own parse tree, so a name
# inside a comment or a string is never reported and a call split across
# lines is still found. It also resolves user-defined wrappers to a fixpoint,
# because rounding is usually one call removed from the name you searched for.
#
# Output is a deterministic inventory, not a verdict. Every hit is printed --
# including ones the scanner marks excluded -- so Coverage can account for
# them. A file with no hits is listed with `hits: 0`; that is a scan result,
# not a clearance.

SCANNER_VERSION <- "2.0"

args <- commandArgs(trailingOnly = TRUE)
include_tests <- "--include-tests" %in% args
args <- args[args != "--include-tests"]
if (length(args) < 1L || !dir.exists(args[1L])) {
  cat("usage: Rscript scan-rounding-calls.R <dir> [--include-tests]\n")
  quit(status = 1L)
}
root <- normalizePath(args[1L])

## ---- catalog ---------------------------------------------------------------
## Tier 1 turns a number into a coarser number. Tier 2 turns a number into
## text and rounds as a side effect of doing so. Both can change what a reader
## sees, which is why the scope clause covers formatting as well as arithmetic.
QUANTIZE <- c("round", "signif", "ceiling", "floor", "trunc",
  "round5", "roundSAS", "round_half_up", "round_up", "round_any", "round_sas")
DISPLAY <- c("formatC", "sprintf", "format", "prettyNum", "as.character",
  "toString", "format.default", "formattable", "scales::number")
## `%/%` quantizes without naming any function, so a name-based search misses
## it entirely -- the cheapest way to hide a rounding defect from a grep.
## `%%` can quantize too, in the `x - x %% unit` idiom, but it is far more
## often a key or parity operation, so it gets its own label rather than
## inflating the quantizer count with noise the reviewer must wade through.
OPERATORS <- c("%/%")
MODULO <- c("%%")
## Context exclusions: sites inside these functions cannot reach a report
## cell. They are reported and labelled, never dropped.
EXCLUDE_FN <- "^(solver_|plot_|gg_|theme_)"

file_pattern <- "[.](R|r|Rmd|rmd|qmd|Rnw)$"
files <- sort(list.files(root, pattern = file_pattern, recursive = TRUE,
  full.names = TRUE))
if (!include_tests) {
  files <- files[!grepl("(^|/)(tests|testthat)/", sub(paste0("^", root, "/?"), "", files))]
}

rel <- function(p) sub(paste0("^", root, "/?"), "", p)

## ---- read source, blanking non-R lines in literate formats -----------------
read_r_lines <- function(path) {
  lines <- suppressWarnings(readLines(path, warn = FALSE))
  if (!grepl("[.](Rmd|rmd|qmd|Rnw)$", path)) return(lines)
  # Keep chunk bodies at their original line numbers; blank everything else so
  # file:line stays true to the file the reviewer will open.
  keep <- logical(length(lines))
  open <- FALSE
  for (i in seq_along(lines)) {
    if (!open && grepl("^\\s*```+\\s*\\{[rR][ ,}]", lines[i])) { open <- TRUE; next }
    if (open && grepl("^\\s*```+\\s*$", lines[i])) { open <- FALSE; next }
    keep[i] <- open
  }
  ifelse(keep, lines, "")
}

## ---- parse ------------------------------------------------------------------
parsed <- list()
for (f in files) {
  lines <- read_r_lines(f)
  pd <- NULL
  ok <- TRUE
  exprs <- tryCatch(parse(text = lines, keep.source = TRUE),
    error = function(e) { ok <<- FALSE; conditionMessage(e) })
  if (ok) pd <- utils::getParseData(exprs)
  parsed[[f]] <- list(lines = lines, pd = pd, exprs = if (ok) exprs else NULL,
    ok = ok, err = if (!ok) exprs else NULL)
}

## ---- map each line to its enclosing top-level function definition ----------
## Needed so a `round()` inside solver_tolerance() can be labelled by context
## rather than by guesswork about the file name.
fn_ranges <- list()
for (f in files) {
  p <- parsed[[f]]
  if (!p$ok) next
  srcrefs <- attr(p$exprs, "srcref")
  rows <- list()
  for (i in seq_along(p$exprs)) {
    e <- p$exprs[[i]]
    if (!is.call(e)) next
    op <- tryCatch(as.character(e[[1]]), error = function(...) "")
    if (!length(op) || !op[1] %in% c("<-", "=", "<<-")) next
    nm <- tryCatch(as.character(e[[2]]), error = function(...) NA_character_)
    rhs <- e[[3]]
    if (length(nm) != 1L || is.na(nm)) next
    if (!is.call(rhs) || !identical(as.character(rhs[[1]])[1], "function")) next
    sr <- srcrefs[[i]]
    rows[[length(rows) + 1L]] <- list(name = nm, line1 = sr[1L], line2 = sr[3L],
      names_used = unique(all.names(rhs)))
  }
  fn_ranges[[f]] <- rows
}

enclosing_fn <- function(f, line) {
  rows <- fn_ranges[[f]]
  if (is.null(rows)) return(NA_character_)
  for (r in rows) if (line >= r$line1 && line <= r$line2) return(r$name)
  NA_character_
}

## ---- wrapper closure --------------------------------------------------------
## A user function is rounding-bearing if it names a catalog function, a
## quantizing operator, or another rounding-bearing user function. Iterating to
## a fixpoint catches chains such as report_x() -> pct_label() -> `%/%`.
all_fns <- list()
for (f in files) for (r in fn_ranges[[f]]) {
  all_fns[[r$name]] <- list(file = f, line = r$line1, names_used = r$names_used)
}
catalog_all <- c(QUANTIZE, DISPLAY, OPERATORS, MODULO)
bearing <- character(0)
repeat {
  added <- FALSE
  for (nm in names(all_fns)) {
    if (nm %in% bearing) next
    used <- all_fns[[nm]]$names_used
    via <- intersect(used, c(catalog_all, bearing))
    if (length(via)) { bearing <- c(bearing, nm); added <- TRUE }
  }
  if (!added) break
}

## ---- collect call sites ------------------------------------------------------
hits <- list()
fallback_files <- character(0)
for (f in files) {
  p <- parsed[[f]]
  if (!p$ok) {
    # Never skip a file silently: fall back to a text scan and say so.
    fallback_files <- c(fallback_files, rel(f))
    for (i in seq_along(p$lines)) {
      pat <- paste0("\\b(", paste(c(QUANTIZE, DISPLAY), collapse = "|"), ")\\(")
      if (grepl(pat, p$lines[i])) {
        hits[[length(hits) + 1L]] <- list(file = rel(f), line = i, col = 1L,
          name = "?", kind = "unparsed", excl = NA_character_,
          src = trimws(p$lines[i]))
      }
    }
    next
  }
  pd <- p$pd
  if (is.null(pd) || !nrow(pd)) next
  tok <- pd[pd$token %in% c("SYMBOL_FUNCTION_CALL", "SPECIAL"), , drop = FALSE]
  if (!nrow(tok)) next
  for (i in seq_len(nrow(tok))) {
    nm <- tok$text[i]
    kind <- if (nm %in% QUANTIZE) "catalog/quantize"
      else if (nm %in% DISPLAY) "catalog/display"
      else if (nm %in% OPERATORS) "operator/quantize"
      else if (nm %in% MODULO) "operator/modulo"
      else if (nm %in% bearing) "wrapper"
      else next
    ln <- tok$line1[i]
    cl <- tok$col1[i]
    encl <- enclosing_fn(f, ln)
    excl <- if (!is.na(encl) && grepl(EXCLUDE_FN, encl))
      paste0("inside ", encl, "() -- context excluded by scanner") else NA_character_
    hits[[length(hits) + 1L]] <- list(file = rel(f), line = ln, col = cl,
      name = nm, kind = kind, excl = excl, src = trimws(p$lines[ln]))
  }
}

## ---- report ------------------------------------------------------------------
cat(sprintf("scanner_version: %s\n", SCANNER_VERSION))
cat(sprintf("root: %s\n", root))
cat("r_version:", R.version.string, "\n")
cat(sprintf("files_scanned: %d\n", length(files)))
per_file <- table(vapply(hits, function(h) h$file, ""))
for (f in files) {
  r <- rel(f)
  n <- if (r %in% names(per_file)) per_file[[r]] else 0L
  cat(sprintf("  file: %s  (hits: %d)\n", r, n))
}

cat("\n--- rounding-bearing user functions (wrapper closure) ---\n")
if (!length(bearing)) {
  cat("  none\n")
} else {
  for (nm in sort(bearing)) {
    inf <- all_fns[[nm]]
    via <- intersect(inf$names_used, catalog_all)
    via2 <- intersect(inf$names_used, bearing)
    cat(sprintf("  %s  %s:%d  [reaches: %s]\n", nm, rel(inf$file), inf$line,
      paste(unique(c(via, via2)), collapse = ", ")))
  }
}

cat("\n--- call sites ---\n")
if (length(hits)) {
  ord <- order(vapply(hits, function(h) h$file, ""),
    vapply(hits, function(h) h$line, 0L),
    vapply(hits, function(h) h$col, 0L))
  for (h in hits[ord]) {
    tag <- if (is.na(h$excl)) h$kind else paste0(h$kind, " | EXCLUDED: ", h$excl)
    cat(sprintf("%s:%d:%d: %s  [%s]\n    %s\n", h$file, h$line, h$col, h$name,
      tag, substr(h$src, 1L, 140L)))
  }
} else {
  cat("  none\n")
}

kinds <- vapply(hits, function(h) h$kind, "")
excluded <- !is.na(vapply(hits, function(h) h$excl, ""))
cat("\n--- summary ---\n")
for (k in c("catalog/quantize", "catalog/display", "operator/quantize",
  "operator/modulo", "wrapper", "unparsed")) {
  cat(sprintf("%s: %d\n", k, sum(kinds == k)))
}
cat(sprintf("excluded_by_context: %d\n", sum(excluded)))
cat(sprintf("candidates_after_context_exclusion: %d\n", sum(!excluded)))
cat(sprintf("total_hits: %d\n", length(hits)))
if (length(fallback_files)) {
  cat(sprintf("unparsed_files: %s\n", paste(fallback_files, collapse = ", ")))
}
cat("note: FIRST PASS ONLY. The parse tree finds named calls and quantizing\n")
cat("note: operators; it cannot see a call assembled at run time via do.call,\n")
cat("note: get, match.fun, or a string-built format. A file with hits: 0 was\n")
cat("note: scanned, not cleared. Label anything you add by reading the source\n")
cat("note: as `exploratory` so it stays distinguishable from this output.\n")
