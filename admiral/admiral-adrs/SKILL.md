---
name: admiral-adrs
description: >
  Derives an ADaM Tumor Response Analysis Dataset (ADRS) using the {admiral}
  and {admiralonco} R packages. Use when a user needs to create ADRS from SDTM
  RS domain data, derive RECIST 1.1 response parameters (overall response,
  confirmed response, best overall response, clinical benefit), or generate
  QC-ready R code following CDISC ADaM and oncology conventions. Requires SDTM
  RS input data, ADSL with randomization and treatment dates, and an ADaM ADRS
  specification.
license: MIT
metadata:
  author: Navitas Data Sciences
  version: "0.1"
  pharmaverse: "true"
  parent: admiral
compatibility: >
  Requires R with admiral, admiralonco, dplyr, lubridate, and pharmaversesdtm
  installed. Requires a completed ADSL dataset with RANDDT and TRTSDT. Designed
  for use in a GxP-compliant oncology trial environment with access to SDTM RS
  domain data and an ADaM ADRS specification.
---

# admiral-adrs

> Shared conventions (library setup, pipe style, date rules, flag convention,
> `# REVIEW:` annotations, `stopifnot()` patterns) are defined in the parent
> [`../SKILL.md`](../SKILL.md). The workflow below is ADRS-specific.

Derives a CDISC-conformant ADRS tumor response dataset using {admiral} and
{admiralonco}. Outputs executable, QC-ready R code covering RECIST 1.1 response
parameters with full derivation traceability.

The primary design challenge in ADRS is the **confirmation logic**: CR and PR
must be supported by a second qualifying assessment ≥28 days later. Best Overall
Response (BOR) follows a strict hierarchy (CR > PR > SD > NON-CR/NON-PD > PD >
NE) and handles NE propagation in ways that manual `case_when()` or `slice_min()`
cannot replicate correctly. Always use `admiralonco` functions — never manual
derivations.

---

## Inputs

Before generating code, confirm the following are available or explicitly noted
as absent:

| Input | Required | Notes |
|---|---|---|
| RS | Yes | One record per tumor assessment per subject; RSSTRESC contains the response category (CR/PR/SD/PD/NE) |
| ADSL | Yes | Provides TRTSDT, RANDDT, treatment labels, population flags |
| ADaM ADRS spec | Yes | Parameter list, PARAMCD/PARAM mapping, confirmation window, clinical benefit definition |
| Study context | Yes | RECIST version (1.0 vs 1.1), assessor (investigator vs BICR), confirmation window, clinical benefit anchor date |

If RS or ADSL are absent, stop and request them.

**Note on pharmaversesdtm test data:** The `pharmaversesdtm` package no longer
exports a plain `rs` object. Use `pharmaversesdtm::rs_onco_recist` for test or
benchmark runs. When working with real study data, load RS from the study's
SDTM package or file path.

---

## Workflow

Follow these steps in order. Generate code section by section, not as a single
block.

### Step 1 — Setup and domain loading

```r
library(admiral)
library(admiralonco)
library(dplyr)
library(lubridate)
library(pharmaversesdtm)

# Load RS domain
# For pharmaversesdtm test data: use rs_onco_recist (plain `rs` no longer exported)
rs   <- pharmaversesdtm::rs_onco_recist
adsl <- adsl  # assumed derived upstream; replace with path/load as needed

# Confirm RS has at least one record
stopifnot(nrow(rs) > 0)
```

### Step 2 — DOMAIN removal

Remove DOMAIN from RS **before** any `derive_param_*()` or `derive_vars_merged()`
calls. admiral errors when DOMAIN exists in both the dataset and a source dataset
passed to these functions.

```r
rs <- rs |> select(-DOMAIN)
```

### Step 3 — Merge ADSL backbone variables

Bring required ADSL variables into the RS dataset before parameter derivation.
At minimum: RANDDT and TRTSDT (clinical benefit anchor and study day reference),
treatment labels, and population flags.

```r
# REVIEW: Confirm which ADSL variables are required by the ADaM ADRS spec.
#   RANDDT is the conventional clinical benefit anchor date; TRTSDT is required
#   for ADY derivation. Add or remove population flags per the spec.
adrs <- rs |>
  derive_vars_merged(
    dataset_add = adsl,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(RANDDT, TRTSDT, TRT01P, TRT01PN, TRT01A, TRT01AN,
                        ITTFL, SAFFL)
  )
```

### Step 4 — Date derivation (ADT, ADTF, ADY)

Derive the analysis date from RSDTC. This must happen **before** any
`derive_param_*()` call — admiralonco response functions use ADT internally for
confirmation window comparisons.

```r
adrs <- adrs |>
  derive_vars_dt(
    dtc             = RSDTC,
    new_vars_prefix = "A",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars    = exprs(ADT)
  )
```

### Step 5 — Analysis value (AVALC, AVAL)

Set AVALC from RSSTRESC and derive the numeric AVAL using the admiralonco helper
`aval_resp()`. This function maps response categories to a monotone numeric scale:
CR=1, PR=2, SD=3, NON-CR/NON-PD=4, PD=5, NE=6.

```r
# REVIEW: Confirm that RSSTRESC values in this study's RS domain align with the
#   RECIST 1.1 CT expected by aval_resp(). Non-standard categories (e.g.
#   "NON-CR/NON-PD" in lymphoma, iRECIST response categories) require a custom
#   lookup if aval_resp() does not map them — do not suppress the resulting NA.
adrs <- adrs |>
  mutate(
    AVALC = RSSTRESC,
    AVAL  = aval_resp(AVALC)
  )
```

### Step 6 — Overall response parameter (OVRLRESP)

Add OVRLRESP records — one per subject per assessment timepoint. This parameter
carries the verbatim response at each visit; it is not confirmation-adjusted.

```r
# REVIEW: PARAMCD and PARAM values must match the ADaM ADRS spec exactly.
#   Adjust filter_source if the study uses a different assessor
#   (BICR: RSEVAL == "INDEPENDENT ASSESSOR") or a different RECIST version.
adrs <- adrs |>
  derive_param_response(
    dataset_adsl  = adsl,
    filter_source = RSEVAL == "INVESTIGATOR" & RSEVALID == "RECIST 1.1",
    source_var    = RSSTRESC,
    set_values_to = exprs(
      PARAMCD = "OVRLRESP",
      PARAM   = "Overall Response by Investigator"
    )
  )
```

### Step 7 — Unconfirmed response flag (RSP)

Add RSP records — one per subject, indicating whether any CR or PR was observed
(unconfirmed). Retained alongside CONFIRMED to enable the ORR verification check
in Step 11.

```r
adrs <- adrs |>
  derive_param_response(
    dataset_adsl  = adsl,
    filter_source = RSEVAL == "INVESTIGATOR" & RSEVALID == "RECIST 1.1",
    source_var    = RSSTRESC,
    resp_val      = c("CR", "PR"),
    set_values_to = exprs(
      PARAMCD = "RSP",
      PARAM   = "Response (Unconfirmed)"
    )
  )
```

### Step 8 — Confirmed response (CONFIRMED)

A CR or PR is confirmed when a second qualifying assessment ≥ `ref_confirm` days
after the first also shows CR or PR. CONFIRMED = "Y" if the subject has at least
one confirmed CR or PR; "N" otherwise.

**Flag convention note:** CONFIRMED uses `"Y"`/`"N"`, not `"Y"`/`NA` — this is
the documented admiralonco contract. See
[Flag convention exception](#flag-convention-exception-for-confirmed-and-cbrespfl)
below. Do not recode `"N"` to `NA`.

```r
# REVIEW: ref_confirm = 28 is the RECIST 1.1 standard for CR/PR confirmation.
#   Confirm this value against the study protocol and SAP — some programs specify
#   21 days, and regulatory precedent exists for other windows. A wrong value
#   silently inflates or deflates confirmed ORR.
adrs <- adrs |>
  derive_param_confirmed_resp(
    dataset_adsl  = adsl,
    filter_source = RSEVAL == "INVESTIGATOR" & RSEVALID == "RECIST 1.1",
    source_var    = RSSTRESC,
    ref_confirm   = 28,       # PLACEHOLDER — confirm from SAP
    set_values_to = exprs(
      PARAMCD = "CONFIRMED",
      PARAM   = "Confirmed Response"
    )
  )
```

### Step 9 — Best overall response (BESTRESP)

BOR applies the RECIST 1.1 hierarchy across all assessments for each subject.
`derive_param_confirmed_bor()` handles confirmation requirements, the NE
propagation rule, and the hierarchy correctly. Never substitute `slice_min(AVAL)`
or manual `case_when()` — these cannot replicate the NE propagation logic.

```r
# REVIEW: missing_as_ne controls how missing assessments are treated in BOR.
#   FALSE (default): missing assessments are ignored (excluded from BOR).
#   TRUE: missing assessments count as NE, which can worsen BOR for subjects
#   with gaps in the assessment schedule.
#   Confirm the per-protocol analysis population definition with the
#   statistical reviewer before committing to either value.
adrs <- adrs |>
  derive_param_confirmed_bor(
    dataset_adsl  = adsl,
    filter_source = RSEVAL == "INVESTIGATOR" & RSEVALID == "RECIST 1.1",
    source_var    = RSSTRESC,
    ref_confirm   = 28,       # must match Step 8
    missing_as_ne = FALSE,    # PLACEHOLDER — confirm from SAP
    set_values_to = exprs(
      PARAMCD = "BESTRESP",
      PARAM   = "Best Overall Response (Confirmed)"
    )
  )
```

### Step 10 — Clinical benefit (CBRESPFL)

Clinical benefit is a durable non-progressive response: CR, PR, or SD sustained
for ≥ `ref_start_window` days from `reference_date`. CBRESPFL = "Y" if criteria
are met; "N" otherwise.

**Flag convention note:** CBRESPFL uses `"Y"`/`"N"`, not `"Y"`/`NA`. Same
admiralonco contract as CONFIRMED — do not recode.

```r
# REVIEW: Two protocol-specific decisions are required here and must both be
#   confirmed from the protocol and SAP before use:
#
#   (1) reference_date — RANDDT is the conventional anchor. Some protocols
#       instead define the 42-day window from the date of the first qualifying
#       response (first SD, PR, or CR). If the protocol means "from first
#       qualifying assessment", compute per-subject first-assessment dates
#       and pass them as reference_date rather than a fixed ADSL variable.
#
#   (2) ref_start_window = 42 — RECIST standard for SD duration. Some studies
#       use 35 or 56 days. Confirm from the protocol.
adrs <- adrs |>
  derive_param_clinbenefit(
    dataset_adsl     = adsl,
    filter_source    = RSEVAL == "INVESTIGATOR" & RSEVALID == "RECIST 1.1",
    source_var       = RSSTRESC,
    reference_date   = RANDDT,    # PLACEHOLDER — confirm anchor from protocol
    ref_start_window = 42,        # PLACEHOLDER — confirm from protocol
    set_values_to    = exprs(
      PARAMCD = "CBRESPFL",
      PARAM   = "Clinical Benefit"
    )
  )
```

### Step 11 — Verification: confirmed vs unconfirmed ORR

Print response counts side-by-side and assert that confirmed ORR cannot exceed
unconfirmed ORR. A confirmed count greater than unconfirmed count signals a
configuration error in the confirmation window.

```r
# Print response parameter summary for QC — include in script output log
response_summary <- adrs |>
  filter(PARAMCD %in% c("RSP", "CONFIRMED", "CBRESPFL")) |>
  count(PARAMCD, AVALC)
print(response_summary)

# Confirmed ORR must not exceed unconfirmed ORR
n_confirmed   <- sum(adrs$PARAMCD == "CONFIRMED" & adrs$AVALC == "Y", na.rm = TRUE)
n_unconfirmed <- sum(adrs$PARAMCD == "RSP"       & adrs$AVALC == "Y", na.rm = TRUE)
stopifnot(n_confirmed <= n_unconfirmed)

# PD is never a confirmed response
stopifnot(!any(
  adrs$PARAMCD == "CONFIRMED" & adrs$AVALC == "Y" &
  adrs$AVAL == aval_resp("PD"),
  na.rm = TRUE
))
```

### Step 12 — Final checks

```r
# Required parameter coverage
required_params <- c("OVRLRESP", "RSP", "CONFIRMED", "BESTRESP", "CBRESPFL")
missing_params  <- setdiff(required_params, unique(adrs$PARAMCD))
if (length(missing_params) > 0) {
  stop("Missing required ADRS parameters: ", paste(missing_params, collapse = ", "))
}

# Uniqueness: one record per subject per subject-level parameter
dup_check <- adrs |>
  filter(PARAMCD %in% c("BESTRESP", "CONFIRMED", "RSP", "CBRESPFL")) |>
  count(STUDYID, USUBJID, PARAMCD) |>
  filter(n > 1)
if (nrow(dup_check) > 0) {
  stop("Duplicate subject-level parameter records found:\n",
       paste(paste(dup_check$USUBJID, dup_check$PARAMCD), collapse = "\n"))
}

# Required variable presence check
required_vars <- c(
  "STUDYID", "USUBJID", "PARAMCD", "PARAM",
  "ADT", "ADTF", "ADY", "AVAL", "AVALC", "TRTSDT"
)
missing_vars <- setdiff(required_vars, names(adrs))
if (length(missing_vars) > 0) {
  stop("Missing required ADRS variables: ", paste(missing_vars, collapse = ", "))
}
```

---

## Flag convention exception for CONFIRMED and CBRESPFL

The admiral family convention is `"Y"` or `NA` — never `"N"` — for flag variables.
ADRS has two named exceptions:

| Variable | Values | Reason |
|---|---|---|
| `CONFIRMED` | `"Y"` / `"N"` | admiralonco contract: `"N"` means assessed but unconfirmed, not missing |
| `CBRESPFL` | `"Y"` / `"N"` | admiralonco contract: same logic as CONFIRMED |

**Do not recode `"N"` to `NA`** for these variables. The `"N"` records are
required by downstream `derive_param_confirmed_bor()` logic to correctly
identify subjects with no confirmed response. Recoding them breaks BOR
derivation.

All other flags in ADRS (ANL01FL, ABLFL, population flags from ADSL) follow the
standard `"Y"` or `NA` convention.

---

## Common errors to avoid

- **Using `rs` instead of `rs_onco_recist`** from pharmaversesdtm — the plain
  `rs` object is no longer exported; the script will fail at load
- **Using `case_when()` or `slice_min(AVAL)` for BOR** — manual BOR derivation
  cannot replicate admiralonco's NE propagation rule and confirmation hierarchy;
  always use `derive_param_confirmed_bor()`
- **Not removing DOMAIN from RS** before `derive_param_*()` calls — causes
  variable conflict errors; DOMAIN must be removed in Step 2, not in the final
  `select()` at the end of the script
- **Hardcoding `ref_confirm = 28`** without a `# REVIEW:` comment — the
  confirmation window is protocol-specific and must come from the SAP; a wrong
  value silently inflates or deflates confirmed ORR
- **Applying `derive_vars_dt()` after `derive_param_response()`** — ADT must
  exist before the response parameter functions run; the functions use ADT for
  confirmation window comparisons
- **Using RANDDT as the clinical benefit anchor without verifying protocol
  intent** — if the protocol defines the 42-day window from the "first
  qualifying response assessment" rather than randomization, a fixed RANDDT will
  misclassify subjects
- **Not printing the confirmed vs unconfirmed ORR comparison** — the omission
  is a silent audit risk; confirmed ORR > unconfirmed ORR indicates a
  derivation error that will not surface without an explicit check
- **Recoding CONFIRMED or CBRESPFL `"N"` to `NA`** — these values are
  meaningful per the admiralonco function contract; recoding breaks downstream
  BOR derivation

---

## Output checklist

Before returning code, verify:

- [ ] DOMAIN removed from RS in Step 2, before any `derive_param_*()` call
- [ ] ADSL merged with at minimum RANDDT, TRTSDT, and population flags before parameter derivation
- [ ] ADT derived with `derive_vars_dt()` from RSDTC, with `flag_imputation = "auto"`
- [ ] AVALC and AVAL (via `aval_resp()`) populated before `derive_param_response()` calls
- [ ] All five parameters present in output: OVRLRESP, RSP, CONFIRMED, BESTRESP, CBRESPFL
- [ ] `# REVIEW:` at PARAMCD/PARAM mapping in Steps 6–10
- [ ] `# REVIEW:` at `ref_confirm` in Steps 8 and 9
- [ ] `# REVIEW:` at `missing_as_ne` in Step 9
- [ ] `# REVIEW:` at `reference_date` and `ref_start_window` in Step 10
- [ ] Confirmed vs unconfirmed ORR comparison printed to console (Step 11)
- [ ] `stopifnot(n_confirmed <= n_unconfirmed)` present (Step 11)
- [ ] PD-never-confirmed assertion present (Step 11)
- [ ] Required PARAMCD coverage check present (Step 12)
- [ ] Uniqueness assertion for subject-level parameters (Step 12)
- [ ] CONFIRMED and CBRESPFL values are `"Y"`/`"N"` — not recoded to `"Y"`/`NA`
