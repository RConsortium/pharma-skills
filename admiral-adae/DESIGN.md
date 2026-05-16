# DESIGN.md — admiral-adae

This document records the design decisions, scope boundaries, and open questions
for the `admiral-adae` skill. It is a living document during the design phase —
decisions will be updated as community input is received and benchmarks are
developed.

---

## Skill Purpose

Derive a CDISC-conformant ADaM Adverse Events Analysis Dataset (ADAE) using the
{admiral} R package. The skill encodes the workflow, function selection logic,
and CDISC conventions an experienced admiral programmer applies — enabling an
AI coding agent to generate QC-ready, audit-traceable R code from SDTM AE, a
completed ADSL, and an ADaM ADAE specification.

---

## Scope

### In scope

- Standard ADAE derivation for parallel-group studies
- Treatment-emergent adverse event (TEAE) flag derivation via `derive_var_trtemfl()`
- Analysis start/end dates and study days (ASTDT, AENDT, ASTDY, AENDY)
- Severity (AESEV, AESEVN), seriousness (AESER), outcome (AEOUT), causality
  (AEREL, AERELN), and action taken (AEACN) from AE SDTM
- Pre-existing condition flag (PREFL) from MH when in scope
- Maximum severity flag (AMAXSEVFL) via `restrict_derivation()`
- SMQ and sponsor-defined grouping flags via `derive_vars_query()`
- SDTM inputs following CDISC SDTMIG conventions
- R implementation using admiral, dplyr, metacore, and xportr
- Code structured for human QC review and regulatory submission

### Out of scope (initial release)

- Non-ADAE ADaM datasets — planned as separate skills
- SAS implementation
- Therapeutic-area-specific extensions (admiralonco, admiralvaccine)
- Integrated summary of safety across multiple studies
- Non-pharmaverse R implementations
- Automatic MedDRA hierarchy look-ups beyond AEDECOD/AEBODSYS carried from AE

---

## Key Design Decisions

### Decision 1: Focused skill (admiral-adae) rather than broad OCCDS skill

**Decision:** Build a focused `admiral-adae` skill covering ADAE only, rather
than a general OCCDS skill covering all occurrence datasets (ADAE, ADCM, ADMH).

**Rationale:**
- Consistent with the `admiral-adsl` precedent — focused skills are more
  testable and have clearer benchmark criteria
- ADAE has the most complex and safety-critical derivation in the OCCDS family:
  TRTEMFL requires protocol-specific inputs (TEAE window) that differ from CM or
  MH derivation logic
- Different OCCDS datasets have meaningfully different variable sets and
  evaluation criteria; a combined skill would be too broad
- A focused skill establishes the pattern for follow-on OCCDS skills
  (admiral-adcm, admiral-admh) without overpromising scope

**Alternative considered:** A single `admiral-occds` skill with conditional
logic by dataset type. Rejected for the same reasons as the `admiral-adam`
alternative in admiral-adsl.

**Status:** Decided. Open to community input.

---

### Decision 2: pharmaversesdtm as the benchmark input source

**Decision:** Use `{pharmaversesdtm}` SDTM datasets as the input source for all
benchmarks, supplemented by synthetic modifications for edge case scenarios.

**Rationale:**
- pharmaversesdtm provides publicly available, CDISC-conformant AE data that
  any contributor can access without restriction
- Ensures benchmarks are fully reproducible across environments
- Consistent with how the admiral package itself structures its test cases

**Known limitation:** `pharmaversesdtm::ae` does not contain AETOXGR. The CTCAE
grading derivation in Step 7 of SKILL.md is commented out for pharmaverse test
data and is present only for use with real study datasets.

**Status:** Decided. Open to community suggestions for additional sources.

---

### Decision 3: TEAE window as the primary # REVIEW: annotation

**Decision:** The `end_window` argument in `derive_var_trtemfl()` is always
annotated with `# REVIEW:` and a placeholder value (30 days) is used
explicitly. The skill never silently applies a default window.

**Rationale:**
- The post-treatment AE window is protocol-specific and safety-critical. An
  incorrect window silently miscategorises adverse events with major submission
  consequences.
- Common values range from 0 days (on-treatment only), 7 days, 28/30 days,
  to "until end of follow-up" depending on the therapeutic area and endpoint.
- The placeholder value (30 days) is chosen to be conservative but is
  explicitly marked to prevent unreviewed use in a submission.

**Status:** Decided.

---

### Decision 4: Selective ADSL merge rather than full merge

**Decision:** SKILL.md instructs the agent to merge only a defined list of ADSL
variables onto ADAE, not all of ADSL.

**Rationale:**
- A full `left_join(adsl, by = c("STUDYID", "USUBJID"))` merges 100+ variables
  from ADSL onto every AE record, inflating dataset size and introducing variable
  naming conflicts with AE variables.
- ADaM specification defines exactly which ADSL variables appear in ADAE.
  Merging extras creates define.xml discrepancies and submission review findings.
- The `exprs()` / `select(!!!adsl_vars)` pattern makes the selection explicit
  and reviewable.

**Status:** Decided.

---

### Decision 5: Progressive disclosure structure for skill instructions

**Decision:** Keep SKILL.md under 500 lines by offloading detailed function
selection rationale to `references/admiral-adae-functions.md` and CDISC variable
conventions to `references/adae-conventions.md`, loaded on demand.

**Rationale:**
- Follows the agentskills.io specification recommendation for progressive
  disclosure
- Prevents SKILL.md from becoming unmanageable as the skill matures
- Allows reference files to be updated independently

**Status:** Decided.

---

### Decision 6: Human review annotations as a first-class output requirement

**Decision:** The skill explicitly requires `# REVIEW:` comments at every
protocol-specific decision point, treated as a required output dimension
evaluated in benchmarks.

**Rationale:**
- TEAE window, causality coding, severity grading scale, SMQ membership lists,
  and PREFL matching strategy are all protocol- and study-specific. Silent
  defaults create submission risk.
- GxP context requires that AI-generated code is reviewable by a qualified
  human. Explicit flags support this without refusing the task.

**Status:** Decided.

---

## Open Questions

### OQ-1: Benchmark scope for TEAE window

Should benchmarks test:

a) Only the standard case (end_window = 30) with a fixed expected output, and
   separately test that `# REVIEW:` annotations are present?
b) Multiple window values as parameterised benchmarks (0, 7, 30 days)?
c) A "deferral" benchmark where the SAP document is deliberately absent and the
   agent is scored on whether it stops and requests it?

**Current inclination:** Option (a) and (c) — correctness benchmark with fixed
window, and a deferral benchmark to test agent behaviour when context is missing.

---

### OQ-2: AETOXGR handling in benchmarks

pharmaversesdtm::ae does not contain AETOXGR. Should benchmarks:

a) Explicitly test the commented-out CTCAE block using synthetic data?
b) Treat CTCAE grading as out of scope for pharmaverse-based benchmarks and
   document this clearly?
c) Add a supplemental benchmark with synthetic AE data that includes AETOXGR?

**Current inclination:** Option (b) for initial release, with option (c) as a
follow-on once the synthetic data generation pattern is established.

---

### OQ-3: PREFL matching strategy evaluation

The PREFL derivation matches AEDECOD to MHDECOD. Should benchmarks assess:

a) Whether the agent correctly implements exact term matching?
b) Whether the agent flags the matching strategy with `# REVIEW:` and notes
   the alternative of body system (AEBODSYS = MHBODSYS) matching?
c) Both?

**Current inclination:** Option (c) — correctness for the standard pattern plus
annotation quality for the protocol-specific matching decision.

---

### OQ-4: AESEQ carry-through vs re-derivation

AE.AESEQ from SDTM may or may not match the intended ADaM sequence. Should
SKILL.md:

a) Instruct the agent to always carry through AE.AESEQ and note it with
   `# REVIEW:`?
b) Always re-derive using `derive_var_obs_number()` for ADaM consistency?
c) Carry through by default and only re-derive when the spec explicitly requires
   a different ordering?

**Current inclination:** Option (c) is most consistent with real-world practice.
Current SKILL.md implements this correctly.

**Status:** Resolved. SKILL.md Step 13 implements option (c).

---

## Planned Benchmarks

| Benchmark | What it tests | Status |
|---|---|---|
| `basic-teae` | Standard TEAE derivation, complete data, all required ADAE variables | In development |
| `sar-window` | Post-treatment SAE window; end_window variation; annotation checking | Planned |
| `severity-mapping` | AESEV/AESEVN derivation; correct `case_when()` mapping; numeric companion | Planned |
| `pre-existing` | PREFL derivation from MH; exact-term vs body-system matching | Planned |
| `smq-grouping` | SMQ flag derivation via `derive_vars_query()`; query dataset structure | Planned |

---

## Planned Follow-On Skills

This skill is the second in the admiral ADaM derivation skill family:

| Skill | Dataset type | Depends on |
|---|---|---|
| `admiral-adsl` | Subject-level (prerequisite) | — |
| `admiral-adae` | Occurrence (this skill) | admiral-adsl |
| `admiral-adtte` | Time-to-event (BDS-TTE) | admiral-adsl |
| `admiral-adex` | Exposure (BDS) | admiral-adsl |
| `admiral-bds` | General BDS findings/efficacy | admiral-adsl |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| 2026-05 | Jeff Dickinson | Initial draft — design phase opened |
