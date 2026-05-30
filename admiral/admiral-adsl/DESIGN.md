# DESIGN.md — admiral-adsl

This document records the design decisions, scope boundaries, and open questions
for the `admiral-adsl` skill. It is a living document during the design phase —
decisions will be updated as community input is received and benchmarks are
developed.

---

## Skill Purpose

Derive a CDISC-conformant ADaM Subject-Level Analysis Dataset (ADSL) using the
{admiral} R package. The skill encodes the workflow, function selection logic,
and CDISC conventions an experienced admiral programmer applies — enabling an
AI coding agent to generate QC-ready, audit-traceable R code from SDTM inputs
and an ADaM specification.

---

## Scope

### In scope

- Standard ADSL derivation for parallel-group and simple crossover studies
- Single-period treatment variables following the TRT01P/TRT01A naming pattern
- All required ADSL variables per ADaMIG v1.3
- Common permissible variables: baseline demographics, disposition, standard
  population flags (ENRLFL, RANDFL, SAFFL, ITTFL, FASFL, PPROTFL)
- SDTM inputs following CDISC SDTMIG conventions
- R implementation using admiral, dplyr, metacore, and xportr
- Code structured for human QC review and regulatory submission

### Out of scope (initial release)

- Non-ADSL ADaM datasets — planned as follow-on skills
- SAS implementation
- Therapeutic-area-specific extensions (admiralonco, admiralvaccine,
  admiralmetabolic)
- Complex multi-period crossover designs (four or more periods)
- Integrated analysis across multiple studies (IADSL)
- Non-pharmaverse R implementations

---

## Key Design Decisions

### Decision 1: Focused skill (admiral-adsl) rather than broad skill (admiral-adam)

**Decision:** Build a focused `admiral-adsl` skill covering ADSL only, rather
than a broad `admiral-adam` skill covering all ADaM dataset types.

**Rationale:**
- Consistent with the `group-sequential-design` precedent in this repo — focused
  skills are more testable and have clearer benchmark criteria
- ADSL has well-defined inputs (DM, EX, DS), predictable outputs, and universal
  applicability across all studies — making it the strongest first candidate
- Different ADaM dataset types (OCCDS, BDS, TTE) require substantially different
  function patterns and conventions; a single skill would be too broad to encode
  reliably
- A focused skill establishes the pattern for a follow-on family
  (admiral-adae, admiral-adtte, admiral-bds) without overpromising scope

**Alternative considered:** A single `admiral-adam` skill with conditional logic
by dataset type. Rejected because evaluation criteria would be difficult to
define and the skill instructions would exceed manageable length.

**Status:** Decided. Open to community input.

---

### Decision 2: pharmaversesdtm as the benchmark input source

**Decision:** Use `{pharmaversesdtm}` SDTM datasets as the input source for all
benchmarks, supplemented by synthetic modifications for edge case scenarios.

**Rationale:**
- pharmaversesdtm provides publicly available, CDISC-conformant SDTM data that
  any contributor can access without restriction
- Ensures benchmarks are fully reproducible across environments
- Consistent with how the admiral package itself structures its test cases
- pharmaverseadam provides reference ADaM outputs for correctness comparison

**Alternative considered:** Synthetic SDTM data generated within each benchmark.
Rejected as harder to maintain and less representative of real-world data.

**Status:** Decided. Open to community suggestions for additional sources.

---

### Decision 3: Progressive disclosure structure for skill instructions

**Decision:** Keep SKILL.md under 500 lines by offloading detailed function
selection rationale to `references/admiral-functions.md` and CDISC variable
conventions to `references/adsl-conventions.md`, loaded on demand.

**Rationale:**
- Follows the agentskills.io specification recommendation for progressive
  disclosure
- Prevents SKILL.md from becoming an unmanageable monolith as the skill matures
- Allows reference files to be updated independently without modifying the core
  skill instructions
- Agents load reference files when the decision context requires them, reducing
  token overhead for simple derivations

**Status:** Decided.

---

### Decision 4: Human review annotations as a first-class output requirement

**Decision:** The skill explicitly requires `# REVIEW:` comments at every
protocol-specific decision point, treating these annotations as a required
output dimension evaluated in benchmarks.

**Rationale:**
- Population flag definitions (SAFFL, ITTFL, PPROTFL), disposition record
  selection, and age grouping cut-points are all study-specific. An agent that
  silently applies default logic creates submission risk.
- GxP context requires that AI-generated code is reviewable by a qualified
  human before use. Explicit review flags support this requirement.
- Makes the skill's outputs safer for use in regulated environments without
  requiring the agent to refuse protocol-specific questions outright.

**Status:** Decided.

---

### Decision 5: xportr + metacore for dataset attribute application

**Decision:** Recommend `{xportr}` and `{metacore}` for applying variable
labels, types, lengths, and order as the final step in ADSL derivation, rather
than base R attribute functions.

**Rationale:**
- xportr is the pharmaverse standard for spec-driven XPT export
- Ensures variable attributes are applied from the ADaM spec metadata, not
  hardcoded in derivation code
- Consistent with submission-ready pharmaverse workflows
- `haven::write_xpt()` is noted as a simpler alternative for non-submission
  contexts

**Status:** Decided. Revisit if xportr interface changes significantly.

---

## Open Questions

These questions are brought to the community for input before the skill is
finalised.

### OQ-1: Benchmark scope for population flags

Population flag derivations (SAFFL, ITTFL, PPROTFL) are highly
protocol-specific. Should benchmarks:

a) Test only the standard logic (e.g. SAFFL = received at least one dose) and
   explicitly mark PPROTFL as out of scope for automated evaluation?
b) Include a benchmark with a defined protocol-specific PPROTFL rule to test
   whether the agent correctly applies `# REVIEW:` annotations and defers?
c) Both — a correctness benchmark for standard flags and a deferral benchmark
   for complex ones?

**Current inclination:** Option (c) — both types of benchmark provide different
and complementary signal.

---

### OQ-2: admiral version pinning in benchmarks

admiral has an active deprecation cycle (3-year window). Should benchmarks:

a) Pin to a specific admiral version and update on a defined schedule?
b) Test against the current CRAN release only?
c) Test against both CRAN and the development version (main branch)?

**Current inclination:** Option (b) for initial release, with a note in
LIFECYCLE tracking that benchmark review should accompany major admiral releases.

---

### OQ-3: Evaluation of `# REVIEW:` annotation quality

The rubric currently assesses whether `# REVIEW:` comments are present at
expected locations. Should it also assess:

a) Whether the comment text accurately describes what needs human review?
b) Whether the agent correctly identifies *unexpected* protocol-specific
   situations not covered by the skill instructions?

**Current inclination:** (a) is in scope for v1 evaluation; (b) is aspirational
and may be better addressed through adversarial benchmark design.

---

### OQ-4: Handling of DOMAIN variable conflicts

The `derive_vars_merged()` function errors if a variable exists in both the
input dataset and the source domain (e.g. DOMAIN). The skill currently
instructs `select(domain, -DOMAIN)` as the fix. Should this be:

a) Kept as an explicit instruction in SKILL.md (current approach)?
b) Moved to `references/admiral-functions.md` under Common Pitfalls?
c) Handled by a pre-processing step recommended in the workflow?

**Current inclination:** Move to the pitfalls section of admiral-functions.md
and add a pre-processing recommendation in the workflow.

**Status:** Resolved. Pitfall #5 in `references/admiral-functions.md` covers the
`-DOMAIN` pre-processing pattern. No changes needed to SKILL.md workflow.

---

## Planned Benchmarks

| Benchmark | What it tests | Status |
|---|---|---|
| `basic-two-arm` | Standard parallel-group, complete data | In development |
| `multi-arm` | Three treatment arms, TRT01P/TRT01A distinction | Planned |
| `missing-dates` | Partial `--DTC` imputation in EX and DS | Planned |
| `early-discontinuation` | EOSSTT/DCSREAS from DS, not all subjects complete | Planned |
| `screen-failure` | Subjects in DM who never received treatment; SAFFL = NA | Planned |

---

## Planned Follow-On Skills

This skill is intended as the first in a family of admiral ADaM derivation skills:

| Skill | Dataset type | Depends on |
|---|---|---|
| `admiral-adsl` | Subject-level (this skill) | — |
| `admiral-adae` | Occurrence (OCCDS) | admiral-adsl |
| `admiral-adtte` | Time-to-event (BDS-TTE) | admiral-adsl |
| `admiral-adex` | Exposure (BDS) | admiral-adsl |
| `admiral-bds` | General BDS findings/efficacy | admiral-adsl |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| 2026-05 | Jeff Dickinson | Initial draft — design phase opened |
