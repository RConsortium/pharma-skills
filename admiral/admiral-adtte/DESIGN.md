# DESIGN.md — admiral-adtte

This document records the design decisions, scope boundaries, and open questions
for the `admiral-adtte` skill.

---

## Skill Purpose

Derive a CDISC-conformant ADaM Time-to-Event Analysis Dataset (ADTTE) using the
{admiral} R package. The skill encodes the event and censoring object pattern,
CDISC structural conventions, and QC annotation requirements that an experienced
admiral programmer applies — enabling an AI coding agent to generate QC-ready,
audit-traceable R code across therapeutic areas.

---

## Scope

### In scope

- Standard ADTTE derivation for parallel-group studies across all therapeutic areas
- `event_source()` / `censor_source()` pattern with named objects
- AVAL derivation in days via `derive_vars_duration()` with `add_one = TRUE`
- CNSR as integer 0/1 with CNSDTDSC and EVNTDESC populated correctly
- Multiple TTE parameters in a single dataset (Step 5+ repeated per PARAMCD)
- Safety TTE endpoints (time to first AE) using AE as source
- Event-free survival endpoints using DS or CE as source
- Structural assertions: CNSR range, AVAL positivity, CNSDTDSC/EVNTDESC, uniqueness
- R implementation using admiral

### Out of scope (initial release)

- Oncology PFS where event dates derive from ADRS milestone assessments —
  noted as a cross-skill dependency in README.md; deriving the ADRS milestone
  dates belongs to `admiral-adrs`
- Competing risks TTE (requires `admiralcm` or custom logic)
- Landmark analysis subsets
- SAS implementation
- Non-pharmaverse R implementations

---

## Key Design Decisions

### Decision 1: Named event_source / censor_source objects, never inline

**Decision:** SKILL.md requires event and censor conditions to be defined as
named objects before `derive_param_tte()`, never as inline expressions.

**Rationale:**
- Named objects can be unit-tested independently of the full derivation call
- Named objects are reusable across PARAMCD calls without copy-paste (a common
  error that causes the censoring logic to diverge between parameters)
- The #166 benchmark showed both agents using the named-object pattern correctly;
  making it explicit in the skill prevents regression

**Status:** Decided.

---

### Decision 2: Three mandatory # REVIEW: locations targeting the #166 gaps

**Decision:** The skill explicitly requires `# REVIEW:` at the event filter
(Step 5), censoring date expression (Step 6), and CNSDTDSC text (Step 6).
These are the three assertion failures shared by both agents in the #166 benchmark.

**Rationale:**
- Event definition (which AEs or DS records constitute the event) is always
  protocol-specific; a wrong filter silently misclassifies subjects
- The censoring date (TRTEDT + 30 days, LSDT, end of study) is also
  protocol-specific and varies widely across therapeutic areas
- CNSDTDSC must exactly match define.xml controlled terminology; a free-text
  mismatch produces submission review findings

**Status:** Decided.

---

### Decision 3: derive_vars_merged() for ADSL, not left_join()

**Decision:** SKILL.md explicitly names `left_join()` as an error to avoid and
requires `derive_vars_merged()`.

**Rationale:**
- The #166 benchmark showed the unskilled agent using `left_join()` for a
  post-derivation ADSL merge, which failed assertion 4. This is a common
  pattern for programmers transitioning from base R or tidyverse-first workflows.
- `derive_vars_merged()` applies admiral's key-variable validation and is
  consistent with how ADSL variables are merged in all other admiral child skills.

**Status:** Decided.

---

### Decision 4: General-purpose skill, not oncology-specific

**Decision:** `admiral-adtte` covers TTE derivation across all therapeutic areas.
Oncology PFS with ADRS milestone event dates is noted as a cross-skill dependency
but not worked through in detail.

**Rationale:**
- ADTTE is used in cardiovascular (time to MACE), respiratory (time to
  exacerbation), and many other areas — scoping to oncology would artificially
  limit the skill's usefulness
- The oncology PFS case adds `admiral-adrs` as a prerequisite and uses the
  ADRS dataset as an event source, which is a skill composition pattern better
  documented in the ADRS skill than here

**Status:** Decided.

---

## Open Questions

### OQ-1: STARTDT variable naming

`derive_param_tte()` creates a STARTDT variable from the `start_date` argument.
Some specs require this to be named TRTSDT or RANDDT in the output. Should the
skill document how to rename or alias STARTDT?

**Current inclination:** Add a note in a future v0.2 — the current skill covers
the standard case where STARTDT is acceptable.

---

### OQ-2: Competing risks

For TTE endpoints with a competing event (e.g., time to CV death with non-CV
death as a competing risk), the standard `derive_param_tte()` approach is
insufficient. Should the skill document this limitation with a referral?

**Current inclination:** Add a note in Common Errors or a future section.

---

## Benchmarks

Benchmarks are tracked as GitHub issues with the `benchmark` and `eval` labels at
https://github.com/RConsortium/pharma-skills/issues.

Issue [#166](https://github.com/RConsortium/pharma-skills/issues/166) is the
existing ADTTE benchmark (ran against `admiral-bds`, +21 pp). Re-running against
this skill is the first priority validation step.

---

## Revision History

| Date | Author | Change |
|---|---|---|
| 2026-08-13 | Jeff Dickinson | Initial draft — created from #166 benchmark failure analysis |
