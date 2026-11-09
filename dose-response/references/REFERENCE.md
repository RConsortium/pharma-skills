# Reference: General Code Generation Rules

This file contains the general rules for generating statistical analysis code in a clinical trial submission context. It applies to all code generation tasks. A skill may also apply to your specific analysis — if so, both this file and the skill must be followed or the code will contain errors.

---

## First Coding Rules

- DO NOT SUBMIT ANY CODE UNTIL EVERY SINGLE RULE HAS BEEN **RECHECKED** AGAINST THE CODE YOU JUST WROTE. THERE ARE LIKELY ERRORS IN YOUR CODE.
- Merging is a last resort if a single dataset cannot answer the user query. Before writing code that merges datasets, recheck the column names of the relevant datasets — the merge may be unnecessary.
- Many routine statistical models have pre-packaged functions in R that output SEs and CIs. If you find yourself writing convoluted code for established statistical analyses, you are doing too much work and it will probably be wrong. Think again.
- Do not write a `.R` file to source it. Write code directly.

---

## Reading from Context

Before writing code, identify the following from your context:

**From MAPPED ENDPOINTS:**
- Statistical method and model specification (`statistical_method`, `statistical_model`)
- Outcome variable (`cdisc_param` — e.g., CHG for change from baseline, AVAL for raw endpoint value)
- Covariates (`covariates` field)
- Grouping or pooling rules (`grouping or pooling rules` field) 
- Endpoint visit (`endpoint_visit`)
- Baseline visit (`baseline_visit`)

**From ADRG GUIDANCE:**
- Efficacy treatment variable (`efficacy_treatment_variable`)
- Efficacy population flag (`efficacy_population_flag`)
- Baseline flag (`baseline_flag`)
- Analysis flag (e.g., `ANL01FL`) — use this to filter to correct records at the endpoint visit

**From DATASET information:**
- Which dataset to use for each endpoint
- Exact column names available in that dataset
- Whether `BASE` exists as a pre-computed baseline column
- Whether a `DTYPE` column exists and what values it takes

---

## Outcome Variable

- Always read `cdisc_param` from the mapped endpoint to determine the outcome
- If `cdisc_param` is `CHG` and a `CHG` column exists in the dataset, use it directly — it is pre-computed and authoritative. Do not compute `AVAL - BASE`.
- If `cdisc_param` is `AVAL`, use `AVAL` directly
- Do not guess the outcome variable from the endpoint name or description alone

---

## Baseline Covariate

- If `BASE` exists in the dataset, use it directly as the baseline covariate
- Do not reconstruct baseline by filtering `ABLFL == 'Y'` or joining from another parameter — `BASE` is pre-computed and known to be correct
- Check dataset columns before assuming `BASE` is present

---

## Record Selection and Filtering

Apply filters in this order:
1. `PARAMCD == <endpoint parameter code>`
2. `AVISIT == <endpoint_visit>` — always filter explicitly on visit; do not rely on analysis flag alone
3. Efficacy population flag `== 'Y'` (from ADRG GUIDANCE)
4. Analysis flag `== 'Y'` (e.g., `ANL01FL`) if specified in ADRG GUIDANCE

**DTYPE:** Do not filter on `DTYPE` unless the SAP or ADRG explicitly specifies it. Check `DTYPE` values to understand derived records, but only apply a filter if explicitly required.

---

## Variable Types: Continuous vs Categorical

| Variable type | Rule |
|--------------|------|
| N-suffixed numeric variables (e.g., `AGEGR1N`, `SEXN`, `RACEN`) | Keep as numeric — do NOT factor unless SAP explicitly states categorical |
| Treatment variable as continuous predictor (e.g., `TRTPN` in trend model) | Keep as numeric |
| Treatment variable as categorical (e.g., dose groups for pairwise comparisons) | Factor in R |
| Site grouping variables (e.g., `SITEGR1`) and individual site (`SITEID`) | Always factor — stored as integers but represent categorical groups |
| Any variable whose `DataType` in define.xml is `text` | Always treat as categorical |

**Why site variables must be factored:** Site grouping variables are stored as integers in ADaM datasets but represent nominal categories, not a numeric scale. Treating them as numeric imposes a false linear relationship across site codes.

---

## Treatment Variable

- Use the variable identified in the ADRG
- If the SAP specifies a continuous treatment, use the numeric version (e.g., `TRTPN`) — do not convert to factor
- Never convert a variable whose name ends in `N` to categorical; use the corresponding character variable (e.g., `TRTP`) if categorical coding is needed

---

## Multi-Dataset Submissions

- Check the ADRG to determine which dataset contains the relevant PARAMCD for each endpoint
- Use the correct dataset for each endpoint

---


## Confidence Intervals

- Always compute 95% CIs unless the SAP specifies otherwise
- Use a function that computes CIs explicitly — do not assume summary output includes CIs
- CIs must be on the quantities of interest (e.g., pairwise differences, LS means, etc), not on intermediate quantities (e.g., individual group means) unless both are needed.

---

## Code Structure Rules

- Always start by reading the data file using the full file path from context
- Always print unique `PARAMCD` and `AVISIT` values in the filtered data to allow downstream verification
- Generate separate code blocks for each endpoint — do not share model objects across endpoints
- Use actual variable names from context — do not use `as.formula()` with strings 
- Prefer straightforward code over helper functions or complex abstractions

---


## Self-Check Checklist

Before returning any code to the user, verify the following checklist line by line. Stopping early will result in numerical errors and non-conformant code.

- [ ] Does this analysis require a skill? If so, verify you followed it exactly. This is your time to go back and correct if you took shortcuts.
- [ ] Every CDISC variable in the statistical model matches the extracted mapped variable description
- [ ] Outcome variable matches `cdisc_param` (CHG vs AVAL)
- [ ] PARAMCD filter value matches the parameter code confirmed in `define.xml` against the endpoint description from the SAP
- [ ] PARAMCD value occurs in the dataset
- [ ] Treatment variable type is correct (continuous vs categorical per model spec)
- [ ] All covariates are mapped based on functional intent described in the SAP, cross-referenced with `define.xml`
- [ ] N-suffixed variables are not factored unless explicitly required by SAP
- [ ] Categorical variables (site, treatment groups, age groups, etc) are factored
- [ ] All grouping and pooling rules quoted from the SAP. 
- [ ] If a site pooling variable appears in the dataset, use the one that corresponds to the SAP rule for the endpoint.
- [ ] `BASE` is used directly without reconstruction
- [ ] `AVISIT` filter is applied explicitly
- [ ] Analysis flag filter is applied if specified in the ADRG 
- [ ] 95% CIs are computed and on the correct quantities
- [ ] `PARAMCD` and `AVISIT` are printed from filtered data
- [ ] Separate code blocks per endpoint
- [ ] No `as.formula()` with strings
- [ ] Code reads data from full file path
- [ ] Correct dataset used for each endpoint (multi-dataset submissions)
- [ ] Code is not returned in a .R file
- [ ] ADaM variable convention questions checked against `ADaMIG_v1.3.pdf` or user, not assumed

If any item fails, fix the code before returning it. **PRIORITIZE CORRECTNESS OVER SPEED.**
