# DESIGN: dose-response

## Purpose
Guide an agent through generating correct R code for dose-response analyses (ANCOVA or ANOVA)
where treatment is a continuous dose variable, including both a linear trend test and pairwise comparisons between 
discrete dose groups.

## Scope

**In scope:**
- Continuous treatment/dose variable
- Linear trend test (treatment as numeric predictor)
- Pairwise comparisons between dose groups (treatment as categorical), 
  with 95% CIs on the differences
- R code generation

**Out of scope:**
- Purely categorical treatment with no dose-response hypothesis
- Nonlinear trend tests or non-linear dose-response modeling (e.g., quadratic trends, Emax models)
- Time-to-event / survival endpoints
- Any language beyond R 

## Expected Inputs
* Clinical trial submission files including SAP, ADRG, `define.xml`, and ADaM dataset(s) 

## Expected Output
- Runnable code implementing two models: one with treatment as continuous 
  (trend test), one with treatment as categorical (pairwise comparisons), 
  according to the variables consistent with the submission context


## Non-Goals
- This skill does not interpret or report results — it only generates 
  the analysis code
- This skill does not handle missing-data imputation strategies. It assumes the dataset is already prepared as needed.