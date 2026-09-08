---
name: rounding
description: >
  Audit R code that prepares CSR/TLF statistics for SAS-compatible rounding
  compliance (ties away from zero, round-once-at-display, fixed trailing-zero
  precision). Make sure to use this skill whenever the user asks to review,
  check, verify, or fix rounding, mentions SAS rounding, half-away-from-zero,
  display precision, trailing zeros, early rounding, mock tables showing 76
  not 76.00, percentages off by 1 at the half point, or names round(),
  formatC(), sprintf(), format(), signif(), prettyNum(), cards::round5,
  tidytlg::roundSAS, or janitor::round_half_up in a clinical-report context --
  even if they don't say the word rounding.
license: MIT
metadata:
  author: Pharma Skills community
  version: "0.9"
  rules-version: "BR-001/002/003 v1.0"
---

# Rounding compliance review

Default to an advisory report. Do not edit source, change policy, or approve a
classification. When the user explicitly asks to file a finding, create one
fix-ready issue in the **audited repository**, not in this skill's repository.

The point of the review is not to find `round()`. It is to establish which
operations can change a number a reader sees or a number that decides which
rows they see, and then to prove what each one actually does. Those are
different questions, and only the second one needs a machine.

## When to Use

Use this skill when the user asks to:

- audit, check, verify, or fix rounding in R reporting code (even if they
  don't say the word "rounding")
- compare R and SAS rounding, or mentions ties-away-from-zero / half-away
- debug trailing-zero or fixed-precision display (e.g. mock tables show
  `76` where the spec requires `76.00`, or `2%` where it requires `2.0%`)
- investigate percentages or statistics "off by 1 at the half point"
- review TLF/CSR/display code that calls `round()`, `formatC()`, `sprintf()`,
  `format()`, `signif()`, `prettyNum()`, `cards::round5`, `tidytlg::roundSAS`,
  or `janitor::round_half_up`, or describes early rounding / round-once-at-display

See also *When NOT to use this skill* at the end.

## Scope example

A repository audit is not limited to installed package code. Treat executable
reporting examples in `Rmd`/`qmd` as report entry paths too: a vignette that
computes a mean, percentage, CI, or p-value and sends it to `rtf_*()`,
`write_rtf()`, a table, or a listing is in scope even when no exported
`report_*()` function calls it. Tests and pure rendering/layout examples stay
visible in Coverage and are excluded unless they themselves generate report
statistics.

## Bundled resources

| File | What it contains | When to use |
|------|-----------------|-------------|
| `references/function-catalog.md` | In-scope/excluded functions, where rounding hides | Step 2 |
| `references/br-001-tie-method.md` | Tie rule, two causes, FAIL signature, versioned-helper fix | Step 4, when BR-001 is in scope |
| `references/br-002-rounding-stage.md` | Stage rule, FAIL signature, remove-early-rounding fix | Step 4, when BR-002 is in scope |
| `references/br-003-display-precision.md` | Display rule, FAIL signature, fixed-character fix | Step 4, when BR-003 is in scope |
| `scripts/scan-rounding-calls.R` | Parse-tree inventory: catalog calls, quantizing operators, wrapper closure | Step 2; its output is never complete coverage |
| `scripts/probe-tie-behavior.R` | Executed tie/stage/display witnesses; `--digits` for per-site precision | Step 5 |
| `assets/report-template.md` | `report.md` structure | Step 6 |

Do NOT read or run these upfront. Use each only when the step directs.

## Required inputs

Collect these before scanning. A rule the request is silent on is
`NOT ASSESSABLE` -- name it as unchecked rather than inventing it.

- **Target**: a local folder or a repo link pinned to a commit, read-only. Pin
  it: an unpinned reference silently stops reproducing when the source moves.
- **Precision spec**: preferred digits and trailing-zero expectation per
  reported statistic. If absent, infer digits from the reporting context
  (literal `digits`, function defaults, table labels, and paired examples) and
  default trailing-zero expectation to `true`. Record the inference and its
  source; use `NOT ASSESSABLE` only when the context supplies no defensible
  precision.
- **Tie policy and its version**, plus the comparison helper the rule owner
  selected and that package's version.
- **Entry paths**: exported report functions, scripts, and executable chunks in
  `.Rmd`/`.qmd`/`.Rnw` that calculate or prepare reported statistics. A caller
  need not be exported: observable reporting behavior makes it in scope.
- **Rule owner**: the named person who will classify each finding. Record the
  name in the report. An unnamed gate is not a gate.
- **Allowlist** (optional): sites the rule owner has already classified. See
  below.

## Procedure

1. **Confirm inputs.** Resolve the list above and the `report.md` path, using
   the source to settle whatever it can settle. Ask about a gap you cannot
   close, but do not let one unanswered question stop the parts of the review
   it does not touch -- see *Missing inputs* below.
2. **Scan the whole repository (first pass only).** Read
   `references/function-catalog.md`, then run `scripts/scan-rounding-calls.R`
   at the repository root—not just `R/`. Confirm Coverage accounts separately
   for every discovered `.R`, `.r`, `.Rmd`, `.rmd`, `.qmd`, and `.Rnw` file;
   use `--include-tests` when tests contain reporting fixtures or executable
   examples. Preserve the full output. The scanner never clears a file, so
   inspect zero-hit literate files and infer where dynamic rounding can hide.
   Label candidates `catalog`, `wrapper`, `operator`, or `exploratory`.
3. **Trace and triage.** Follow each reporting path, including standalone
   vignette/helper chunks that compute statistics before table or file output.
   Export status is irrelevant. Keep each reachable reporting operation as a
   row; move layout, encoding, solver, plotting, and ordinary test-only hits to
   Coverage with reasons. Trace paired sites (early rounding + downstream
   display or decision) together.
4. **Resolve against the rules.** For each row state namespace, method/class,
   and version, then read the matching `references/br-00x-*.md` for the FAIL
   signature and fix.
5. **Prove.** Run `scripts/probe-tie-behavior.R`, then
   re-run it with `--digits N` for each distinct precision the target displays
   -- a witness at the wrong precision does not test the site. Unexecuted
   claims are not evidence.

   Write `report.md` incrementally -- skeleton first, witnesses second. Draft
   the inventory table and Coverage before perfecting any witness script, so
   a run always delivers a report even if time runs short. Keep witness
   scripts small: source the target read-only and reuse the probe's
   dependency-free half-away arithmetic inline (`sign(x) *
   trunc(abs(x) * 10^d + 0.5) / 10^d`, plus `+ 0` for the signed-zero guard)
   rather than building a large bespoke harness. A report with before-only
   witnesses and a stated fix pattern beats no report.

   Every finding needs two executed witnesses: the **before**, showing the
   observed value against the policy value, and the **after**, showing that the
   fix you recommend actually produces the policy value. A recommendation no one
   has run is a guess, and it is the part of the report a reader is most likely
   to paste into the codebase. If the selected package helper cannot be run,
   demonstrate the fix *pattern* with the probe's dependency-free half-away
   arithmetic and say that is what you did -- still recommend the versioned
   package, and note that its exact behavior at inexact ties was not confirmed
   here.
6. **Verdict and write.** Per row: Tie / Stage / Display as `PASS` / `FAIL` /
   `NOT ASSESSABLE`; Overall is `FAIL` if any rule fails, `NOT ASSESSABLE`
   if none fails and at least one is uncheckable, else `PASS`. Compliant
   helper-plus-formatter paths pass -- do not rewrite them.

   ALWAYS use the exact structure in `assets/report-template.md` (see
   *Report structure* below) for the audit deliverable; do not invent or rename
   report sections.

7. **File a target-repository issue only when explicitly authorized.** First
   search the target repository's open issues for the exact paths/rules to
   avoid duplicates. For each actionable FAIL, create at most one issue in the
   target repository with: affected `file:line` paths; actual versus required
   behavior; a minimal executed reproduction; a bounded remediation pattern;
   acceptance criteria covering positive and negative ties, round-once stage
   where applicable, fixed-width display, and signed zero; and the pinned
   target commit. Link the audit report, verify the issue after posting, and
   report its URL. If the target is read-only, authorization is missing, or the
   finding is only `NOT ASSESSABLE`, leave a local issue draft instead.

## Report structure

ALWAYS use this exact template from `assets/report-template.md`:

```markdown
# Rounding compliance report -- <package> <version/commit>
Target / Environment / Policy / Status / Verdict (one line each)
## Summary -- one row per (operation, entry path) with Tie/Stage/Display/Overall
## Appendix A. Coverage -- files scanned, hits, excluded sites with file:line + reason
## Appendix B. Evidence (executed) -- policy-vs-actual witnesses per row
## Appendix C. Limitations -- missing specs and blind spots
```

Fill every section from executed output; an empty section is a missing section,
not a clean section.

## One row per operation *and* entry path

The same site can be compliant on one path and defective on another. A shared
formatter that receives a value already rounded half-away is a no-op; the same
formatter receiving an unrounded value is itself the rounding step, and
`formatC()` and `sprintf()` are not half-away. Give each
(operation, entry path) pair its own row. A single collapsed verdict for a
shared helper is wrong in one direction or the other.

Split by *distinct behavior*, not by syntax. Two calls to the same operation on
the same path with the same precision -- both bounds of a confidence interval,
say -- share one row; note that it covers two call sites. Splitting them inflates
the inventory without adding a verdict. Conversely, quantization and display
formatting in the same function are distinct behaviors and get separate rows:
`(x * 10) %/% 1 / 10` (Tie) vs `paste0(n, "%")` (Display) is two rows, not one.

Every in-scope operation gets a row, including compliant and allowlisted ones.
Give the allowlisted helper its own definition-site row (e.g.
`R/rounding-helpers.R:10` `trunc(abs(x) * scale + 0.5)` as a reviewed `PASS`
with tie-vector evidence), in addition to the per-call-site rows that use it.
Recording it only in the allowlist table drops it out of the count a reader
uses to check your coverage, which is the opposite of what an allowlist is for.

When early rounding and its downstream display are paired (BR-002), mark
Stage `FAIL` on both rows and state they are one finding -- the early site is
the primary defect, the downstream row carries the same Stage verdict so the
pair stays together when sorted or filtered.

In Coverage, quote the scanner's `files_scanned` and `total_hits` verbatim;
do not recount `R/` files by hand.

Signed zero is part of BR-001, not a fourth rule. A site that renders `-0`
fails the tie rule; do not open a separate verdict column for it, and do not
fail a downstream no-op formatter for a signed zero its caller produced --
the finding belongs to the operation that created the value.

## Two causes, never one

When a formatting call diverges from policy, say which of these is acting --
usually both, and they can push in opposite directions:

1. **Tie mode.** `base::round()` is half-to-even at a true tie.
2. **Binary representation.** Most decimal ties are not stored exactly, so the
   result follows the stored value rather than the printed one.

Do not compress this into "the function uses banker's rounding". That claim is
false for `formatC()` and `sprintf()`, and it predicts the wrong direction for
half the inputs. At zero decimals every `x.5` tie is stored exactly, so cause 1
acts alone; decimals bring in cause 2. This is why the probe, not source
reading, is the evidence.

Also check that no displayed value is a signed zero: a small negative value
formatted at the display precision can render as `-0` or `-0.0`. Probe this
only with in-domain inputs for that entry path. An out-of-domain negative
probe (e.g. negative counts for a rate that takes counts and durations) is
recorded as not scored -- input unreachable -- never as a `FAIL`. Score `FAIL`
only when a reachable input can render a signed zero.

## Allowlist

An allowlist entry is a classification the rule owner already made, not a
reason to stop looking. An entry needs a reason, a source version, and an
approver. Report the site as a reviewed `PASS`, keep it visible in Coverage,
and return it to full review if the named source has changed since approval --
otherwise the allowlist quietly becomes a blind spot. Never add, edit, or infer
an entry yourself; proposing one to the rule owner is the most you may do.

## Missing inputs: narrow the verdict, don't abandon the review

Most gaps make particular cells unassessable rather than making the review
impossible, and the two need opposite responses.

First, try to close the gap from the source. `NAMESPACE` and `@export` tags
usually settle the entry points; a call with a literal `digits` argument
carries its own precision. A gap you can close by reading is not a blocker, and
listing it as one is a false blocker that costs the reader a real audit.

If a gap survives that, infer the narrowest defensible display expectation from
the reporting context: literal `digits`, function defaults, table labels, and
paired examples. Default trailing zeros to required. Record the inference with
its exact source and assess the Display cell against it. Use `NOT ASSESSABLE`
only if no such context exists. That says nothing about its tie method, nothing
about its rounding stage, and nothing whatever about the other statistics.

A review that reports nothing because one input was missing is worse than one
that proves what it can and states exactly what it could not: the reader learns
nothing from the first and can act on the second.

## Stop and escalate

Stop the whole review only when no trustworthy evidence is obtainable at all:

- the source cannot be read or located;
- no report entry point can be identified, even from `NAMESPACE`;
- `probe-tie-behavior.R` reports an unexpected result -- this environment does
  not behave as the rule references describe, so no witness from it can be
  trusted;
- the target documents a convention that conflicts with the stated policy, so
  which rule applies is a question for the rule owner, not for you.

Record the blocker and stop. Everything else is a `NOT ASSESSABLE` cell in a
report you still deliver.

## Target-issue mode

Use this mode only for a user-authorized, evidence-backed `FAIL`. The issue is
a handoff to an implementer, not another audit: give it one defect cluster,
source anchors, the exact observed/policy values, a non-prescriptive fix
boundary, and executable acceptance tests. Never open an issue merely to
repeat scanner candidates, layout/encoding exclusions, or missing policy.

## When NOT to use this skill

Do not use for non-numeric reports, statistical-method validation,
or independent QC replacement. If the user only wants "why do
R and SAS differ in rounding" explained, answer directly. If stage or precision
are out of scope, name the unchecked rules instead of narrowing silently.
