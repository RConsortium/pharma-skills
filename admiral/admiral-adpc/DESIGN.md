# DESIGN.md — admiral-adpc

This document records the design decisions, scope boundaries, and open questions
for the `admiral-adpc` skill.

---

## Skill Purpose

Derive a CDISC-conformant ADaM Pharmacokinetic Concentrations Analysis Dataset
(ADPC, also called ADNCA when used as NCA input) using the {admiral} R package.
The skill encodes the dose-relative time derivations, dosing-record handling,
BLQ conventions, and QC annotation requirements that an experienced admiral PK
programmer applies — enabling an AI coding agent to generate QC-ready R code that
produces analysis-ready input for non-compartmental analysis (NCA) tools such
as {PKNCA}.

---

## Scope

### In scope

- ADPC derivation from SDTM PC and EX, with ADSL and VS for covariates
- Single- and multiple-dose studies, including expanding EX intervals into
  individual dosing records with `create_single_dose_dataset()`
- Nominal and actual relative time variables: NFRLT, AFRLT, NRRLT, ARRLT, MRRLT
  with FRLTU/RRLTU, PCRFTDTM, ATPTREF, BASETYPE per reference dose
- Previous/next dose lookup with `derive_vars_joined()` (never `lag()`/`lead()`)
- DOSE parameter records alongside concentration records (dose input for NCA)
- Planned and actual dose (DOSEP, DOSEA, DOSEU)
- BLQ handling as derived records (`DTYPE = "HALFLLOQ"`), keeping the original
  record, plus pre-dose copy records (`DTYPE = "COPY"`) for the next dose
- Multiple matrices (plasma, urine) via PARCAT1 and multiple analytes via a
  PARAMCD lookup table
- Baseline covariates (HTBL, WTBL, BMIBL) from VS
- Structural assertions: uniqueness, ASEQ, DTYPE consistency, time-variable checks
- R implementation using admiral, following `ad_adpc.R` and the `pk_adnca` vignette

### Out of scope (initial release)

- Computing NCA parameters (Cmax, AUC, half-life) and building ADPP — this is
  {PKNCA} / {aNCA}'s job. The skill prepares ADPC for those tools and points to
  them, but does not reimplement NCA.
- ADPPK (population PK) — planned as a separate `admiral-adppk` skill that
  reuses this skill's time derivations
- Urine collection-interval derivations (amount excreted over PCDTC–PCENDTC)
- Metabolite-to-parent ratios and multi-analyte derived parameters
- SAS implementation
- Non-pharmaverse R implementations

---

## Key Design Decisions

### Decision 1: Anchor on the admiral ADPC template, not first principles

**Decision:** The skill's workflow follows the step order of admiral's
`ad_adpc.R` template and `pk_adnca` vignette (admiral 1.4.x), annotated with
why each step exists and where agents go wrong.

**Rationale:**
- ADPC has many interdependent time variables; the template's order (dates →
  NFRLT → dose expansion → first/previous/next dose → AFRLT/ARRLT → NRRLT →
  DTYPE records → BASE → ASEQ) avoids circular dependencies
- `pharmaverseadam::adpc` is produced by this template, which gives benchmarks
  a reference dataset to compare against
- Agents without guidance tend to hand-roll relative times with `difftime()`
  and `lag()`, which breaks on multiple-dose data and unsorted inputs

**Status:** Decided.

---

### Decision 2: admiral functions for all dose-relative time derivations

**Decision:** SKILL.md requires `derive_var_nfrlt()` for nominal time,
`derive_vars_joined()` for previous/next dose, and `derive_vars_duration()` for
AFRLT/ARRLT. `difftime()`, `as.numeric()` date subtraction, and
`lag()`/`lead()` dose matching are named as errors.

**Rationale:**
- Previous-dose matching must use the dosing record before each sample time,
  not the previous row; `lag()` silently fails when PC and EX are interleaved
- `derive_vars_duration(out_unit = "HOURS")` keeps units explicit and
  consistent with FRLTU/RRLTU

**Status:** Decided.

---

### Decision 3: BLQ values handled with derived DTYPE records, not overwritten

**Decision:** The original BLQ record is kept with AVALCAT1 = "<BLQ" and AVAL
missing; imputed values go on a derived record with `DTYPE = "HALFLLOQ"`
created by `derive_extreme_records()`. Pre-dose BLQ samples supplied with
PCSTRESN = 0 (as in the CDISC pilot) keep AVAL = 0 and are not imputed.
ANL01FL/ANL02FL tell downstream tools which records to use.

**Rationale:**
- Overwriting AVAL loses traceability and fails ADaM derived-record conventions
- NCA-specific BLQ rules (0 before Tmax, LLOQ/2 after, exclude trailing BLQ)
  belong in the NCA tool's configuration, not baked into ADPC
- In `pharmaversesdtm::pc`, 48% of records are BLQ (largely placebo subjects),
  so this choice has a large effect on the output

**Status:** Decided.

---

### Decision 4: Mandatory # REVIEW: locations

**Decision:** The skill requires `# REVIEW:` at:
1. Nominal time mapping (PCTPT → NFRLT, `range_method`, treatment duration)
2. Missing dose-time imputation (EX in the CDISC pilot is date-only, so dose
   times impute to 00:00 and ARRLT is approximate)
3. BLQ imputation rule (LLOQ/2 vs 0) and ANL flag definitions
4. Planned dose (DOSEP) mapping from treatment arm
5. Subject inclusion (placebo / never-dosed subjects excluded)

**Rationale:** Each is a protocol- or SAP-specific choice that changes NCA
results silently if wrong.

**Status:** Decided.

---

### Decision 5: Skill name ADPC, with ADNCA as a trigger term

**Decision:** The skill is `admiral-adpc`, matching admiral's template name.
"ADNCA", "PK concentrations", and "NCA input dataset" are trigger phrases.

**Rationale:** admiral and pharmaverseadam use ADPC; CDISC's ADaM NCA
implementation guide uses ADNCA for the same structure. Users will ask for
either.

**Status:** Decided.

---

## Open Questions

### OQ-1: ADaMIG-NCA variable set

Should the skill target the variables in CDISC's ADaM implementation guide for
NCA, or admiral's template variable set? They overlap heavily but are not
identical.

**Current inclination:** Follow admiral's template for v0.1 and list known
ADaMIG-NCA differences in a reference file.

---

### OQ-2: PKNCA hand-off

Should the skill include an example of passing ADPC to `PKNCA::PKNCAconc()` /
`PKNCAdose()`, so users see the NCA step end-to-end?

**Current inclination:** Yes, as a short optional section — it shows which
ADPC variables NCA needs, without the skill computing NCA itself.

---

### OQ-3: Records for never-dosed subjects

The template drops subjects with no nonzero dose. Some studies keep placebo
subjects in ADPC with an analysis flag instead.

**Current inclination:** Follow the template (drop) and require a `# REVIEW:`.

---

### OQ-4: Special visit values in derive_var_nfrlt()

admiral PR [#3199](https://github.com/pharmaverse/admiral/pull/3199) adds a
`special_values` argument (with `nfrlt_special()`) so unscheduled and
end-of-study visits can get fixed NFRLT values such as 99998.

**Decision for v0.1:** Ignore `special_values`. The skill targets CRAN admiral
1.4.x and handles unscheduled visits with `set_values_to_na` plus a `# REVIEW:`.
Revisit once a CRAN release includes #3199.

---

## Benchmarks

Benchmarks are tracked as GitHub issues with the `benchmark` label at
https://github.com/RConsortium/pharma-skills/issues.

Planned first benchmark: derive ADPC from `pharmaversesdtm::pc`, `ex` and `vs`
with `pharmaverseadam::adsl`, and compare key variables (NFRLT, AFRLT, ARRLT,
DTYPE counts, DOSE records) against `pharmaverseadam::adpc`. This gives a
reference dataset to check against, not just a rubric.

Issue [#172](https://github.com/RConsortium/pharma-skills/issues/172) (NCA
exposure metrics) depends on `admiralpk`, which is not on CRAN. It should be
rewritten to use `pharmaversesdtm::pc` with {PKNCA} and compared against
`pharmaverseadam::adpp`.

---

## Revision History

| Date | Author | Change |
|---|---|---|
| 2026-10-15 | Jeff Dickinson | Initial draft — scoped from the admiral ADPC template, `pk_adnca` vignette, and #172 benchmark findings |
