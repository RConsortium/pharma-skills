# DESIGN.md — admiral-adrs

This document records the design decisions, scope boundaries, and open questions
for the `admiral-adrs` skill.

---

## Skill Purpose

Derive a CDISC-conformant ADaM Tumor Response Analysis Dataset (ADRS) using the
{admiral} and {admiralonco} R packages. The skill encodes the workflow, function
selection logic, and oncology-specific conventions an experienced admiralonco
programmer applies — enabling an AI coding agent to generate QC-ready,
audit-traceable R code from SDTM RS and a completed ADSL dataset.

---

## Scope

### In scope

- ADRS derivation for RECIST 1.1 oncology studies (investigator assessment)
- Five standard ADRS parameters: OVRLRESP, RSP, CONFIRMED, BESTRESP, CBRESPFL
- Date derivation (ADT, ADTF, ADY) from RSDTC using admiral functions
- Confirmed response per RECIST 1.1 (CR/PR ≥28 days apart)
- Best Overall Response with NE propagation via `derive_param_confirmed_bor()`
- Clinical benefit (SD/PR/CR ≥42 days from reference date)
- Verification: confirmed ORR ≤ unconfirmed ORR, PD-never-confirmed assertions
- SDTM RS inputs following CDISC SDTMIG conventions
- R implementation using admiral and admiralonco

### Out of scope (initial release)

- iRECIST response criteria
- BICR (Blinded Independent Central Review) assessor — covered as a `# REVIEW:`
  note in the PARAMCD filter, but not a separate workflow
- RECIST 1.0, Cheson criteria, Lugano classification, irRC
- SAS implementation
- ADTTE derivation — planned as a separate `admiral-adtte` skill
- Integrated tumor burden (sum of longest diameters) — requires raw measurement
  data not captured in RSSTRESC
- Non-pharmaverse R implementations

---

## Key Design Decisions

### Decision 1: admiral-adrs as a separate skill rather than admiral-onco covering ADRS + ADTTE

**Decision:** Build a focused `admiral-adrs` skill covering tumor response only,
rather than a combined `admiral-onco` skill covering ADRS and ADTTE.

**Rationale:**
- ADTTE uses base `admiral` functions (`derive_param_tte()`, `event_source()`,
  `censor_source()`), not `admiralonco` — the package dependency differs
- ADTTE is not oncology-specific; it is used in cardiovascular, respiratory,
  and other therapeutic areas with time-to-event endpoints
- The parent `admiral/SKILL.md` routing table already plans a separate
  `admiral-adtte` slot
- Focused skills are more testable: each benchmark can be attributed to a
  specific gap without cross-contamination from a different workflow

**Alternative considered:** A single `admiral-onco` skill covering ADRS + ADTTE.
Rejected because PFS ADTTE for oncology often derives event dates from ADRS
milestone assessments, but the TTE derivation workflow itself belongs in
`admiral-adtte`; the link between them is documented in the relationship table
in README.md.

**Status:** Decided.

---

### Decision 2: CONFIRMED and CBRESPFL as "Y"/"N" exceptions to the flag convention

**Decision:** The skill explicitly documents that CONFIRMED and CBRESPFL use
`"Y"`/`"N"` values, not `"Y"`/`NA`, and instructs the agent not to recode them.

**Rationale:**
- `derive_param_confirmed_resp()` and `derive_param_clinbenefit()` produce `"N"`
  for subjects who were assessed but did not meet the response criterion. The
  `"N"` is meaningful — it distinguishes "assessed, not confirmed" from "not yet
  assessed" (which would appear as a missing record, not a `"N"` value).
- Recoding `"N"` to `NA` breaks downstream `derive_param_confirmed_bor()`, which
  uses the presence of explicit `"N"` CONFIRMED records to correctly handle the
  BOR hierarchy for non-responding subjects.
- This is a documented admiralonco contract, not a CDISC deviation.
- The skill flags this prominently to prevent a common agent error: applying the
  general `"Y"`/`NA` convention from the parent skill and breaking the pipeline.

**Status:** Decided.

---

### Decision 3: RANDDT as the default clinical benefit reference date, with mandatory REVIEW annotation

**Decision:** SKILL.md uses `RANDDT` as the placeholder for `reference_date` in
`derive_param_clinbenefit()` but requires a `# REVIEW:` comment explaining the
alternative (per-subject first-qualifying-assessment date).

**Rationale:**
- RANDDT is the conventional anchor in RECIST-based clinical benefit definitions
  per most regulatory guidance, but the literal RECIST 1.1 wording ("≥42 days
  from first SD/PR/CR assessment") implies a per-subject first-assessment anchor.
- The #167 benchmark identified this as a real failure point: the unskilled agent
  computed per-subject first-assessment dates (literal reading) while the skilled
  agent used RANDDT (conventional reading) — both are defensible but they produce
  different subject counts.
- A `# REVIEW:` comment forces the programmer to resolve this before submission,
  rather than silently accepting the default.

**Status:** Decided.

---

### Decision 4: RSP parameter retained for ORR verification

**Decision:** The skill derives an RSP (unconfirmed response) parameter and
includes a mandatory `stopifnot(n_confirmed <= n_unconfirmed)` assertion.

**Rationale:**
- Confirmed ORR greater than unconfirmed ORR is logically impossible but has
  occurred in practice when the confirmation window is mis-specified (e.g.,
  `ref_confirm = 2` interpreted as 2 weeks instead of 2 days). The assertion
  catches this silently.
- The #167 benchmark penalised the skilled agent for not printing the confirmed
  vs unconfirmed ORR comparison; the unskilled agent produced this output and
  scored higher on that assertion. The skill now requires it explicitly.

**Status:** Decided.

---

### Decision 5: pharmaversesdtm::rs_onco_recist as the test data object

**Decision:** SKILL.md documents that the plain `rs` object is no longer
exported from pharmaversesdtm and instructs the agent to use `rs_onco_recist`.

**Rationale:**
- Both agents in the #167 benchmark independently discovered this at runtime,
  adding turns and token overhead. Encoding it in the skill avoids the discovery
  cost on every run.
- `rs_onco_recist` is the correct RECIST 1.1 oncology test dataset; it has 8
  subjects and 66 records, sufficient for confirming the derivation pipeline.

**Status:** Decided.

---

## Open Questions

### OQ-1: BICR assessor as a first-class workflow step

Should the skill include a Step 6b for BICR-assessed response parameters, or
treat BICR as a `# REVIEW:` note within the filter condition?

**Current inclination:** `# REVIEW:` note only for initial release — most
oncology submissions use investigator assessment as primary, with BICR as a
sensitivity analysis derived by the same code path with a different filter.

---

### OQ-2: ANL01FL for primary analysis population

ADRS often includes an ANL01FL flag to mark records in the primary analysis
population (e.g., subjects with ≥1 evaluable post-baseline assessment). Should
the skill add a Step 11 for ANL01FL derivation?

**Current inclination:** Yes for v0.2 — ANL01FL is protocol-specific and needs
a `# REVIEW:` annotation, consistent with the pattern in admiral-bds.

---

### OQ-3: Benchmark for the RANDDT vs first-assessment anchor ambiguity

Should there be a dedicated benchmark that tests whether the agent correctly
identifies the clinical benefit anchor ambiguity and annotates it with
`# REVIEW:`?

**Current inclination:** Yes — this is the highest-risk silent failure in ADRS
derivation and warrants a targeted eval case.

---

## Benchmarks

Benchmarks are tracked as GitHub issues with the `benchmark` and `eval` labels at
https://github.com/RConsortium/pharma-skills/issues.

The existing #167 benchmark (`[benchmark][admiral-bds] ADRS derivation`) serves
as the initial eval for this skill — the skill was not yet available when that
benchmark ran. Re-running #167 against this skill will establish the baseline
delta vs. the old admiral-bds routing.

---

## Revision History

| Date | Author | Change |
|---|---|---|
| 2026-08-13 | Jeff Dickinson | Initial draft — created from #167 benchmark failure analysis |
