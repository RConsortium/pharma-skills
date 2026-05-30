# DESIGN.md — admiral-bds

Design decisions, scope boundaries, and open questions for the `admiral-bds`
skill.

---

## Skill Purpose

Derive CDISC-conformant ADaM BDS (Basic Data Structure) datasets from SDTM
findings domains using the {admiral} R package. Initial scope covers ADVS
(vital signs) and ADLB (laboratory values) — the two most universally required
BDS datasets across clinical studies. The skill encodes the workflow, function
selection logic, and CDISC conventions for AI-assisted generation of QC-ready,
audit-traceable R code.

---

## Scope

### In scope (initial release)

- ADVS derivation from SDTM VS domain
- ADLB derivation from SDTM LB domain
- Standard BDS structure: PARAM/PARAMCD, ADT/ADY, AVISIT/AVISITN, AVAL/AVALC
- Baseline flagging (ABLFL), baseline values (BASE/BASEC)
- Change from baseline (CHG) and percent change from baseline (PCHG)
- Reference range variables for ADLB (ANRLO, ANRHI, ANRIND, BNRIND)
- Primary analysis flag (ANL01FL)
- Visit windowing via spec-driven VISIT lookup
- SDTM inputs following CDISC SDTMIG conventions
- R implementation using admiral, dplyr, lubridate

### Out of scope (initial release)

- ADEG (ECG), ADRS (response), ADEF (efficacy findings) — planned follow-on
- CTCAE toxicity grade derivation beyond ADLB (ATOXGR) — planned
- Date-driven visit windowing (ADY-range-based AVISIT assignment) — planned
- Therapeutic-area-specific admiral extensions (admiralonco, admiralvaccine)
- Multiple baseline types (BASETYPE) beyond a single pre-dose window
- Integrated/pooled datasets across studies
- SAS implementation

---

## Key Design Decisions

### Decision 1: Focused skill for BDS findings (ADVS + ADLB) rather than all BDS

**Decision:** Build a skill covering ADVS and ADLB, establishing the BDS
pattern. Not a single skill for all BDS types.

**Rationale:**
- Consistent with the `admiral-adsl` precedent — focused skills have clearer
  benchmark criteria and are easier to evaluate
- ADVS and ADLB are present in nearly every clinical study submission,
  giving immediate broad utility
- BDS sub-types beyond findings (TTE, exposure) require substantially different
  function patterns; they belong in separate child skills
- Establishes the BDS derivation pattern for follow-on skills (ADEG, ADRS, etc.)

**Alternative considered:** A single BDS skill covering all findings dataset
types. Rejected because ADLB normal-range logic, toxicity grading, and shift
table derivations would make the skill too long and difficult to evaluate.

**Status:** Decided. Open to community input.

---

### Decision 2: Visit assignment via spec-driven lookup table, not SDTM passthrough

**Decision:** AVISIT is always assigned from a lookup table defined in the
ADaM spec, not passed through from SDTM VISIT.

**Rationale:**
- SDTM VISIT contains protocol visit names; AVISIT is an ADaM-defined grouping
  that may consolidate multiple SDTM visits or rename them for analysis
- Direct passthrough would silently produce incorrect results when VISIT and
  AVISIT diverge (common in dose-titration, rollover, and long-term extension
  studies)
- Spec-driven lookup makes the mapping auditable and easily reviewed

**Note on date-driven windowing:** Some studies assign AVISIT based on ADY
falling within protocol-defined windows rather than matching VISIT names. The
current skill covers the simpler lookup approach; date-driven windowing will be
added in a subsequent version.

**Status:** Decided.

---

### Decision 3: `restrict_derivation()` + `derive_var_extreme_flag()` for ABLFL

**Decision:** Baseline flagging must use `restrict_derivation()` +
`derive_var_extreme_flag()`, not `mutate()` or `filter()` with manual logic.

**Rationale:**
- `restrict_derivation()` scopes the derivation to a pre-dose window without
  dropping records, preserving all observations in the output dataset
- Manual `mutate()` approaches frequently leave residual flags on incorrect
  records when subjects have complex pre-treatment histories
- Consistent with the idiomatic admiral approach and admiral documentation

**Status:** Decided.

---

### Decision 4: BASETYPE deferred to initial release out-of-scope

**Decision:** Multiple baseline types (BASETYPE) are noted as an out-of-scope
item for the initial skill release. The skill documents where BASETYPE would be
added but does not derive it by default.

**Rationale:**
- Multiple baseline types (e.g. last pre-dose AND last pre-treatment) are
  required in a minority of studies; they add workflow complexity
- Including in scope would require benchmark scenarios that are not commonly
  available from pharmaversesdtm
- The code scaffolding for BASETYPE is straightforward once the single-baseline
  pattern is established — this is a minimal extension

**Status:** Decided. Planned for a future version.

---

## Open Questions

### OQ-1: Visit windowing — lookup vs. date-driven

When should the BDS skill switch from lookup-based visit assignment to
date-driven windowing?

a) Always use the lookup table; document date-driven windowing in a separate
   reference section?
b) Detect when VISIT-to-AVISIT mapping is one-to-many and automatically
   suggest the windowing approach?
c) Include a step-specific fork in the workflow for both patterns?

**Current inclination:** Option (c) — a conditional workflow step with a clear
indicator of which pattern applies.

---

### OQ-2: ADLB normal range population

Should the skill derive ANRLO/ANRHI by:

a) Carrying through LB.LBSTNRLO and LBSTNRHI directly (current approach)?
b) Using a central lab's reference range table from an external dataset?

Many sponsors use site- or lab-specific reference ranges that are not in the LB
domain. Handling this is study-specific.

**Current inclination:** Document option (b) as a `# REVIEW:` comment in the
ADLB step, instructing the user to confirm the source of normal range data.

---

### OQ-3: Uniqueness key for ADVS

ADVS uniqueness keys depend on the study. Standard key is
USUBJID + PARAMCD + AVISITN, but vital signs recorded in triplicate or with
a positional variable (VSPOS) require additional variables.

Should the uniqueness assertion be:

a) Left to the user to define (current approach — the skill provides the
   pattern with a `# REVIEW:` comment)?
b) Derived from the spec at runtime and inserted automatically?

**Current inclination:** Option (a) — document the pattern with a clear
`# REVIEW:` comment.

---

## Planned Benchmarks

| Benchmark | What it tests | Status |
|---|---|---|
| `advs-basic` | Standard ADVS with SBP, DBP, pulse; baseline and change derivations | Planned |
| `adlb-basic` | Standard ADLB with chemistry panel; normal ranges, ANRIND, BNRIND | Planned |
| `adlb-ctcae` | ADLB with CTCAE toxicity grade derivation | Planned |
| `advs-missing-dates` | Partial VSDTC imputation; correct ADT and ADTF | Planned |
| `advs-triplicate` | Multiple records per visit; DTYPE = "AVERAGE" pattern | Planned |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| 2026-05 | Jeff Dickinson | Initial draft — design phase opened |
