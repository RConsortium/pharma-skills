#!/usr/bin/env Rscript
## Render the user-facing conversation of a Claude Code session into
## <out>/prompt.md and <out>/prompt.html: user inputs and Claude's text
## replies, including progress updates between tool calls. Tool calls, tool
## output and thinking are excluded; questions asked through AskUserQuestion
## and plans through ExitPlanMode are kept with the user's answers. Claude's
## markdown (bold, italic, inline code, colored HTML spans, tables with their
## column alignment) is rendered as written. Every message is stamped with its
## local date and time, and every session segment with its start time.
##
## Each session is a segment under <out>/segments/, so a follow-up in a new
## session appends to the log instead of replacing it.
##
## Usage:
##   Rscript conversation_log.R --out <dir> [--title <text>] [--watch]
##           [--session <log.jsonl> ...] [--all] [--interval <s>] [--idle <min>]
##
##   --out       directory for prompt.md / prompt.html (created if missing)
##   --session   session log(s); default: the log of $CLAUDE_CODE_SESSION_ID
##               under ~/.claude/projects/
##   --all       keep the whole session; by default the log starts at the
##               user message that loaded the simulation skill (if found)
##   --watch     re-render whenever the log changes; exit after --idle
##               minutes without change (default 60), re-rendering once more
##
## Exit status 2: the session log could not be located.

`%||%` <- function(a, b) if (is.null(a)) b else a

CSS <- '
:root { --bg:#ffffff; --fg:#1f2328; --muted:#656d76; --border:#d0d7de;
  --user-bg:#f6f8fa; --user-bar:#8c959f; --accent:#d97757; --code-fg:#8250df;
  --code-bg:#f4f0ff; --th-bg:#f6f8fa; --pre-bg:#f6f8fa; --link:#0969da; }
@media (prefers-color-scheme: dark) { :root { --bg:#0d1117; --fg:#e6edf3;
  --muted:#8d96a0; --border:#30363d; --user-bg:#161b22; --user-bar:#6e7681;
  --code-fg:#d2a8ff; --code-bg:#251d3a; --th-bg:#161b22; --pre-bg:#161b22;
  --link:#4493f8; } }
body { background:var(--bg); color:var(--fg); max-width:980px; margin:0 auto;
  padding:24px 16px 64px; font:15px/1.6 -apple-system, BlinkMacSystemFont,
  "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif; }
h1 { font-size:24px; margin:0 0 4px; }
.meta { color:var(--muted); font-size:13px; }
.session { margin:28px 0 4px; padding-bottom:4px; border-bottom:1px solid var(--border);
  color:var(--muted); font-size:13px; font-weight:600; }
.head { margin:22px 0 6px; font-size:12px; font-weight:600; color:var(--muted); }
.head.user::before { content:"\\25CF  "; color:var(--user-bar); }
.head.claude::before { content:"\\25CF  "; color:var(--accent); }
.msg.user { white-space:pre-wrap; overflow-wrap:anywhere; background:var(--user-bg);
  border-left:3px solid var(--user-bar); border-radius:6px; padding:10px 14px; }
.msg.claude > :first-child { margin-top:0; }
.note { margin:14px 0; color:var(--muted); font-size:13px; font-style:italic; }
strong { font-weight:700; }
a { color:var(--link); }
code { font-family:ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size:.88em; color:var(--code-fg); background:var(--code-bg);
  padding:.1em .35em; border-radius:4px; }
pre { background:var(--pre-bg); border:1px solid var(--border); border-radius:6px;
  padding:12px 14px; overflow-x:auto; line-height:1.45; }
pre code { color:inherit; background:none; padding:0; font-size:.86em; }
table { display:block; max-width:100%; overflow-x:auto; border-collapse:collapse;
  margin:12px 0; }
th, td { border:1px solid var(--border); padding:6px 12px; vertical-align:top; }
th { background:var(--th-bg); font-weight:600; }
th:not([align]) { text-align:left; }
blockquote { margin:0; padding:0 12px; border-left:3px solid var(--border);
  color:var(--muted); }
'

## GFM as Claude Code renders it: no smart punctuation, sub/superscript or
## TeX math that would alter the text, and no CDN scripts so the page is
## self-contained.
MD_OPTIONS <- c("-smart", "-subscript", "-superscript", "-latex_math", "-js_math",
                "-js_highlight", "-cross_refs", "+table", "+strikethrough",
                "+tasklist", "+autolink")

parse_args <- function(args) {
  opt <- list(out = NULL, session = character(), title = "Conversation log",
              watch = FALSE, all = FALSE, interval = 5, idle = 60)
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (a %in% c("--watch", "--all")) {
      opt[[sub("^--", "", a)]] <- TRUE
      i <- i + 1
      next
    }
    if (i == length(args)) stop("missing value for ", a)
    v <- args[i + 1]
    switch(a,
           "--out" = opt$out <- v,
           "--session" = opt$session <- c(opt$session, v),
           "--title" = opt$title <- v,
           "--interval" = opt$interval <- as.numeric(v),
           "--idle" = opt$idle <- as.numeric(v),
           stop("unknown argument ", a))
    i <- i + 2
  }
  if (is.null(opt$out)) stop("--out is required")
  opt
}

locate_sessions <- function(paths) {
  if (length(paths) == 0) {
    id <- Sys.getenv("CLAUDE_CODE_SESSION_ID")
    if (nzchar(id)) {
      paths <- Sys.glob(file.path(path.expand("~/.claude/projects"), "*",
                                  paste0(id, ".jsonl")))
    }
  }
  paths <- paths[file.exists(paths)]
  if (length(paths) == 0) {
    message("conversation_log: cannot locate the session log; ",
            "pass --session <path to the session .jsonl>")
    quit(status = 2)
  }
  normalizePath(paths)
}

read_log <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  ## the last line may be half-written while the session is live
  entries <- lapply(lines, function(l) {
    tryCatch(jsonlite::fromJSON(l, simplifyVector = FALSE),
             error = function(e) NULL)
  })
  Filter(Negate(is.null), entries)
}

block_texts <- function(content) {
  if (is.character(content)) return(paste(content, collapse = "\n"))
  out <- character()
  for (b in content) {
    if (identical(b$type, "text")) out <- c(out, b$text)
    if (identical(b$type, "image")) out <- c(out, "[image]")
  }
  paste(out, collapse = "\n\n")
}

clean_user_text <- function(x) {
  x <- gsub("(?s)<system-reminder>.*?</system-reminder>", "", x, perl = TRUE)
  if (grepl("<local-command-(stdout|stderr|caveat)>|<bash-(input|stdout|stderr)>", x)) {
    return("")
  }
  if (grepl("<command-name>", x, fixed = TRUE)) {
    name <- sub("(?s).*<command-name>(.*?)</command-name>.*", "\\1", x, perl = TRUE)
    args <- ""
    if (grepl("<command-args>", x, fixed = TRUE)) {
      args <- sub("(?s).*<command-args>(.*?)</command-args>.*", "\\1", x, perl = TRUE)
    }
    args <- trimws(args)
    return(if (nzchar(args)) paste(trimws(name), args) else "")
  }
  trimws(gsub("\n{3,}", "\n\n", x))
}

is_skill_marker <- function(e) {
  m <- if (is.list(e$message)) e$message else list()
  if (identical(e$type, "user")) {
    x <- block_texts(m$content %||% "")
    return(grepl("<command-name>[^<]*simulat", x, perl = TRUE) ||
             (isTRUE(e$isMeta) &&
                grepl("Base directory for this skill:[^\n]*simulat", x, perl = TRUE)))
  }
  if (identical(e$type, "assistant") && is.list(m$content)) {
    for (b in m$content) {
      if (identical(b$type, "tool_use") && identical(b$name, "Skill") &&
          grepl("simulat", b$input$skill %||% "")) return(TRUE)
    }
  }
  FALSE
}

format_ask <- function(input) {
  qs <- vapply(input$questions %||% list(), function(q) {
    opts <- vapply(q$options %||% list(), function(o) {
      paste0("- **", o$label, "** — ", o$description %||% "")
    }, character(1))
    paste0("**", q$question, "**\n\n", paste(opts, collapse = "\n"))
  }, character(1))
  paste(qs, collapse = "\n\n")
}

format_answer <- function(x) {
  m <- regmatches(x, gregexpr('"([^"]*)"="([^"]*)"', x))[[1]]
  if (length(m) == 0) return(x)
  paste(sub('^"([^"]*)"="([^"]*)"$', "\\1 → \\2", m), collapse = "\n")
}

extract_items <- function(entries, all = FALSE) {
  items <- list()
  pending <- list()
  marker <- NA_integer_
  push <- function(kind, e, text, idx, mid = NA_character_) {
    items[[length(items) + 1]] <<- list(kind = kind, time = e$timestamp %||% NA,
                                        text = text, idx = idx, mid = mid)
  }
  for (idx in seq_along(entries)) {
    e <- entries[[idx]]
    if (isTRUE(e$isSidechain) || isTRUE(e$isCompactSummary)) next
    if (is.na(marker) && is_skill_marker(e)) marker <- idx
    if (identical(e$type, "queue-operation")) {
      if (identical(e$operation, "remove") && identical(e$reason, "absorbed_mid_turn")) {
        push("user_mid", e, e$content %||% "", idx)
      }
      next
    }
    msg <- if (is.list(e$message)) e$message else list()
    content <- msg$content
    if (identical(e$type, "user")) {
      if (isTRUE(e$isMeta)) next
      if (is.list(content) &&
          any(vapply(content, function(b) identical(b$type, "tool_result"), logical(1)))) {
        for (b in content) {
          kind <- if (identical(b$type, "tool_result")) pending[[b$tool_use_id %||% ""]]
          if (!is.null(kind)) {
            push(if (kind == "ask") "answer" else "plan_reply", e,
                 block_texts(b$content %||% ""), idx)
          }
        }
        next
      }
      x <- clean_user_text(block_texts(content %||% ""))
      if (!nzchar(x)) next
      push(if (grepl("^\\[Request interrupted by user", x)) "note" else "user", e, x, idx)
      next
    }
    if (identical(e$type, "assistant") && is.list(content)) {
      mid <- msg$id %||% NA_character_
      for (b in content) {
        if (identical(b$type, "text") && nzchar(trimws(b$text))) {
          n <- length(items)
          if (n > 0 && identical(items[[n]]$kind, "claude") && identical(items[[n]]$mid, mid)) {
            items[[n]]$text <- paste(items[[n]]$text, b$text, sep = "\n\n")
          } else {
            push("claude", e, b$text, idx, mid)
          }
        } else if (identical(b$type, "tool_use") && identical(b$name, "AskUserQuestion")) {
          pending[[b$id]] <- "ask"
          push("claude", e, format_ask(b$input), idx)
        } else if (identical(b$type, "tool_use") && identical(b$name, "ExitPlanMode")) {
          pending[[b$id]] <- "plan"
          push("claude", e, paste0("**Plan**\n\n", b$input$plan %||% ""), idx)
        }
      }
    }
  }
  if (!all && !is.na(marker)) {
    starts <- which(vapply(items, function(it) {
      it$kind %in% c("user", "user_mid") && it$idx <= marker
    }, logical(1)))
    if (length(starts) > 0) items <- items[max(starts):length(items)]
  }
  items
}

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\n", "&#10;", x, fixed = TRUE)
}

## Raw HTML that Claude writes on purpose (e.g. colored spans) is kept; any
## other "<" outside code is escaped so that text like <trial_name> is shown
## instead of being swallowed as an unknown tag.
KEEP_TAG <- paste0("(?:/?(?:span|font|br|b|i|u|s|em|strong|del|ins|mark|sub|sup|",
                   "small|kbd|code|pre|a|img|div|p|details|summary|table|thead|",
                   "tbody|tr|th|td|hr|ul|ol|li|h[1-6])\\b[^<>]*>|https?://|!--)")

protect_markdown <- function(md) {
  lines <- strsplit(md, "\n", fixed = TRUE)[[1]]
  fence <- NULL
  for (k in seq_along(lines)) {
    tok <- regmatches(lines[k], regexpr("^\\s*(`{3,}|~{3,})", lines[k]))
    if (length(tok) == 1) {
      tok <- trimws(tok)
      if (is.null(fence)) {
        fence <- tok
        next
      }
      if (substr(tok, 1, 1) == substr(fence, 1, 1) && nchar(tok) >= nchar(fence)) {
        fence <- NULL
        next
      }
    }
    if (!is.null(fence)) next
    parts <- regmatches(lines[k], gregexpr("(`+)(?:(?!\\1).)+?\\1", lines[k], perl = TRUE),
                        invert = NA)[[1]]
    plain <- seq(1, length(parts), by = 2)
    parts[plain] <- gsub(paste0("<(?!", KEEP_TAG, ")"), "&lt;", parts[plain], perl = TRUE)
    lines[k] <- paste(parts, collapse = "")
  }
  if (!is.null(fence)) lines <- c(lines, fence)
  lines
}

fmt_time <- function(ts) {
  t <- as.POSIXct(sub("Z$", "", ts), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  if (is.na(t)) return("")
  format(t, "%Y-%m-%d %H:%M", tz = "")
}

render_segment <- function(items, sid) {
  out <- c(sprintf('<div class="session">Session %s · started %s</div>',
                   substr(sid, 1, 8), fmt_time(items[[1]]$time)), "")
  user_block <- function(label, text, time) {
    c(sprintf('<div class="head user">%s · %s</div>', label, fmt_time(time)),
      sprintf('<div class="msg user">%s</div>', html_escape(text)), "")
  }
  for (it in items) {
    out <- c(out, switch(
      it$kind,
      user = user_block("User", it$text, it$time),
      user_mid = user_block("User (sent while Claude was working)", it$text, it$time),
      answer = user_block("User (answer)", format_answer(it$text), it$time),
      plan_reply = user_block("User (plan response)", it$text, it$time),
      note = c(sprintf('<div class="note">%s · %s</div>',
                       html_escape(sub("^\\[(.*)\\]$", "\\1", it$text)), fmt_time(it$time)), ""),
      claude = c(sprintf('<div class="head claude">Claude · %s</div>', fmt_time(it$time)),
                 '<div class="msg claude">', "", protect_markdown(it$text), "", "</div>", "")
    ))
  }
  out
}

write_atomic <- function(lines, path) {
  tmp <- file.path(dirname(path), paste0(".", basename(path), ".tmp"))
  con <- file(tmp, open = "w", encoding = "UTF-8")
  writeLines(lines, con)
  close(con)
  file.rename(tmp, path)
}

render <- function(opt, sessions, live) {
  seg_dir <- file.path(opt$out, "segments")
  dir.create(seg_dir, recursive = TRUE, showWarnings = FALSE)
  for (p in sessions) {
    sid <- sub("\\.jsonl$", "", basename(p))
    items <- extract_items(read_log(p), all = opt$all)
    if (length(items) == 0) next
    start <- as.POSIXct(sub("Z$", "", items[[1]]$time), format = "%Y-%m-%dT%H:%M:%OS",
                        tz = "UTC")
    target <- file.path(seg_dir, paste0(format(start, "%Y%m%dT%H%M%S", tz = "UTC"),
                                        "_", sid, ".md"))
    old <- list.files(seg_dir, pattern = paste0("_", sid, "\\.md$"), full.names = TRUE)
    write_atomic(render_segment(items, sid), target)
    unlink(setdiff(normalizePath(old), normalizePath(target)))
  }
  segs <- sort(list.files(seg_dir, pattern = "^[0-9].*\\.md$", full.names = TRUE))
  body <- unlist(lapply(segs, readLines, warn = FALSE, encoding = "UTF-8"))
  status <- if (live) " · live, refreshes every 30 s" else ""
  md <- file.path(opt$out, "prompt.md")
  write_atomic(c(sprintf('<div class="meta">Last updated %s%s</div>',
                         format(Sys.time(), "%Y-%m-%d %H:%M %Z"), status), "", body), md)
  css <- tempfile(fileext = ".css")
  writeLines(CSS, css)
  meta <- list(css = css, title = opt$title)
  if (live) meta[["header-includes"]] <- '<meta http-equiv="refresh" content="30">'
  tmp <- file.path(opt$out, ".prompt.tmp.html")
  markdown::mark_html(md, output = tmp, meta = meta, options = MD_OPTIONS)
  file.rename(tmp, file.path(opt$out, "prompt.html"))
  unlink(css)
  invisible(file.path(opt$out, "prompt.html"))
}

watch <- function(opt, sessions) {
  ## the pid file doubles as a heartbeat: a second watcher started while this
  ## one is alive sees a fresh mtime and exits (no signals, so also safe on Windows)
  pidf <- file.path(opt$out, ".watch.pid")
  if (file.exists(pidf) &&
      difftime(Sys.time(), file.mtime(pidf), units = "secs") < max(30, 3 * opt$interval)) {
    message("conversation_log: a watcher is already running for ", opt$out)
    return(invisible())
  }
  on.exit({
    try(render(opt, sessions, live = FALSE), silent = TRUE)
    unlink(pidf)
  }, add = TRUE)
  last <- NA
  idle_from <- Sys.time()
  repeat {
    writeLines(as.character(Sys.getpid()), pidf)
    mt <- max(file.mtime(sessions))
    if (is.na(last) || mt > last) {
      last <- mt
      idle_from <- Sys.time()
      try(render(opt, sessions, live = TRUE), silent = TRUE)
    } else if (difftime(Sys.time(), idle_from, units = "mins") > opt$idle) {
      break
    }
    Sys.sleep(opt$interval)
  }
}

main <- function() {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  dir.create(opt$out, recursive = TRUE, showWarnings = FALSE)
  opt$out <- normalizePath(opt$out)
  sessions <- locate_sessions(opt$session)
  if (opt$watch) {
    watch(opt, sessions)
  } else {
    cat(render(opt, sessions, live = FALSE), "\n")
  }
}

main()
