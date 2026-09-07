# DESIGN.md -- `rounding`

Design record for the `rounding` skill, per `LIFECYCLE.md` phase 1. Living
document; updated as benchmarks and community input arrive.

Charter: [`RConsortium/pharma-skills` issue #208](https://github.com/RConsortium/pharma-skills/issues/208).
Background: ai4csr chapters `06-workflow-rounding.qmd` (problem, the three
rules, the scope clause) and `07-workflow-rounding-skill.qmd` (workflow brief,
task contract, acceptance criteria). Chapter 07 deliberately bounds its own
design to BR-001 and points readers here for the three-rule version.

## Purpose

Audit R code that prepares clinical-report statistics against a stated rounding
policy, and produce a draft report a named rule owner can classify.

## Scope

### In scope

- BR-001 tie method (half away from zero; never a signed zero)
- BR-002 rounding stage (calculate unrounded, round once at display)
- BR-003 display precision (specified per statistic, trailing zeros preserved)
- R source trees, including literate sources (`.Rmd`, `.qmd`, `.Rnw`)
- Operations reachable from named report entry points

### Out of scope

- Editing source, changing policy, approving a classification, posting an issue
- Statistical-method validation, or replacing independent QC
- Non-numeric reports (text padding, column alignment)
- SAS or Python source
- Deciding whether a value was *intended* as an exact decimal tie -- that is a
  human judgment the report must surface, not resolve

## Key design decisions

### 1. Advisory only, with a named human gate

Rounding policy is organizational, not technical: a language default is an
implementation choice, not a rule. The skill therefore proves behavior and
stops. The rule owner's name is a required input and appears in the report,
because an unnamed gate is not a gate.

### 2. Parse tree, not grep

`scan-rounding-calls.R` walks R's parse tree. A regex scan reports names inside
comments and strings, mislabels `my_round()` as `round()`, misses calls split
across lines, and cannot see `%/%` quantization at all. It also silently skips
lowercase `.r` files -- which is how a broad search produces a confident false
clean report, the risk ai4csr chapter 07 names as the main one.

The parse tree also lets the scanner resolve user wrappers to a fixpoint, so
`report_x() -> pct_label() -> %/%` surfaces without the reviewer guessing.

### 3. The scanner's blind spot is documented and seeded

The parse tree cannot see a call assembled at run time. The scanner says so in
its own output, the catalog reference repeats it, and the benchmark fixture
seeds exactly that case (`do.call(sprintf, list(spec, x))`, which produces zero
hits) so a run that misses it is measurably worse rather than invisibly worse.

### 4. Evidence must survive a surprise

`probe-tie-behavior.R` records every check and exits nonzero at the end rather
than aborting at the first unexpected result. The script *is* the evidence, so
a surprising result must still be printed.

### 5. Witnesses at the precision the site actually uses

The probe is parameterised (`--digits`). A fixed zero-decimal vector cannot
witness a site that displays two decimals, and at zero decimals only one of the
two causes is even visible.

### 6. No dependency required to produce a policy value

The probe carries its own half-away arithmetic, so BR-002 and BR-003 witnesses
are producible with no rounding package installed. The earlier version emitted
`SKIPPED` for the central BR-002 witness on a bare machine. The built-in is for
generating evidence; the *fix* a report recommends is still a versioned package
helper, and the probe cross-checks against one when present.

### 7. One row per operation **and** entry path

A shared formatter is a no-op where it receives an already-rounded value and is
itself the rounding step where it does not. `formatC()` and `sprintf()` are not
half-away, so the distinction decides the verdict. A single collapsed verdict
for a shared helper is wrong in one direction or the other.

### 8. Two causes, kept apart

Tie mode and binary representation are separate causes that can push in
opposite directions. "It uses banker's rounding" is false for `formatC()` and
predicts the wrong direction for half the inputs.

### 9. Allowlist as a classification, not a silencer

An entry needs a reason, a source version, and an approver; the site stays
visible in Coverage and returns to review when the named source changes. The
agent may propose an entry and may never add one.

### 10. A missing input narrows the verdict; it rarely stops the review

Benchmark iteration 1 caught this as a regression: v0.3 stopped an entire audit
over a missing display spec and reported nothing, where v0.2 marked only the
Display cells NOT ASSESSABLE and delivered both other rules in full. The cause
was a contradiction in the skill text -- "Required inputs" scoped a silent rule
to a per-row NOT ASSESSABLE while "Stop and escalate" listed precision as a
whole-review blocker, and the blunt rule won. v0.4 separates the two tiers
explicitly and tells the agent to close what it can from the source first
(`NAMESPACE` settles entry points), since v0.3 also raised false blockers.

### 11. A recommendation nobody executed is a guess

v0.3 produced no fix witnesses because no half-away package was installed, while
v0.2 witnessed every fix. Since the recommendation is the part of a report most
likely to be pasted into the codebase, v0.4 requires an executed after-witness
and allows the probe's built-in half-away arithmetic to demonstrate the pattern
when the selected package is absent, with that substitution stated.

## Open questions

- Should the skill offer a machine-readable inventory (JSON/CSV) alongside
  `report.md` for downstream tracking across releases?
- Cross-language scope: the rules apply equally to Python reporting code, but
  the scanner is R-only. Separate skill, or a second scanner?
- How should the allowlist detect that a source has changed -- content hash per
  site, or rely on the package version?
