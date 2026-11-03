# DESIGN: dose-response

## Purpose
Guide an agent through generating correct R/SAS code for dose-response analyses (ANCOVA or ANOVA)
where treatment is a continuous dose variable, 
including both a linear trend test and pairwise comparisons between 
discrete dose groups.

## Scope

**In scope:**
- Continuous treatment/dose variable
- Linear trend test (treatment as numeric predictor)
- Pairwise comparisons between dose groups (treatment as categorical), 
  with 95% CIs on the differences
- R and SAS code generation

**Out of scope:**
- Purely categorical treatment with no dose-response hypothesis
- Time-to-event / survival endpoints
- Any language beyond R and SAS

## Expected Inputs
- Prerequisite: This skill assumes `references/submission-orientation.md` has been completed to extract endpoint mappings, 
  statistical methods, and variable names from the SAP, ADRG, and define.xml.
- An identified outcome variable (e.g., change from baseline, or raw 
  endpoint value)
- A continuous treatment/dose variable
- Any model covariates (e.g., baseline score, site)
- Population and analysis-record filters
- Specific dose levels, if pairwise comparisons at named levels are needed

This skill assumes the calling agent has already resolved these inputs 
(e.g., via upstream endpoint-mapping steps) — it does not perform 
endpoint extraction or variable mapping itself.

## Expected Output
- Runnable code implementing two models: one with treatment as continuous 
  (trend test), one with treatment as categorical (pairwise comparisons)
- Pairwise LS mean differences with 95% confidence intervals
- Code that never derives pairwise comparisons from the continuous model

## Non-Goals
- This skill does not interpret or report results — it only generates 
  the analysis code
- This skill does not handle missing-data imputation strategies (e.g., 
  LOCF) — assumes the dataset is already prepared as needed