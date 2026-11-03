---
name: dose-response
description: Generate R or SAS code for dose-response ANCOVA/ANOVA analyses where treatment dose is a continuous variable. Covers linear trend testing and pairwise group comparisons with 95% CIs. Triggers on dose-response, test for trend, pairwise comparisons among dose groups, ANCOVA with continuous treatment variable (e.g., TRTPN, TRTAN, etc).
---

# dose-response

This skill guides you through generating correct statistical code for a dose-response ANCOVA analysis. Endpoint mappings, ADRG guidance, and dataset information should already be available in your context from the extraction/mapping steps in `references/submission-orientation.md` — do not re-run those steps for this skill.

## Usage

Use this skill when the user asks for code to test a dose-response relationship with a continuous treatment variable, including when pairwise comparisons between dose groups are also requested.

Do not use this skill when treatment is purely categorical with no dose-response hypothesis, or for time-to-event endpoints.

## Steps
0. REQUIRED: Before generating any code, read `references/submission-orientation.md` and 
   complete STEP 1 and STEP 2 to extract endpoint mappings from the SAP, ADRG, and define.xml.
   If these STEPs were completed already in this session, you may skip this step.
1. Determine which pattern is needed:
   - Trend test only → Pattern 1
   - Trend test + pairwise comparisons → Pattern 2
   - Multiple endpoints, same design → repeat Pattern 2 per endpoint

2. Apply the Key Rules below before writing any model code.

3. Write the code following the relevant Example pattern below, substituting actual variable names, dataset paths, PARAMCD values, visit names, and covariates from context.

4. Before returning code, check the dose-response-specific self-check items below, then apply the general code generation self-check checklist
   from references/REFERENCE.md.

## Key Rules

**The Two-Model Requirement**

A dose-response analysis with pairwise comparisons always requires two separate models. This is not optional.

- **Model A — continuous treatment (trend test):** treatment variable enters as numeric. Tests for a linear trend across dose levels. Produces the treatment coefficient, SE, and p-value for trend. In R, use `emmeans` with `at = list(treatment_var = c(dose levels))` to get LS means at each dose level.
- **Model B — categorical treatment (pairwise comparisons):** treatment variable coded as a factor (R) or declared in `CLASS` (SAS). Same outcome, covariates, population filter, and visit filter as Model A. Produces pairwise LS mean differences, 95% CIs, and p-values. In R, call `emmeans` without the `at` argument; use `contrast(..., 'revpairwise', infer = TRUE)` for 95% CIs on the pairwise differences.

**Why two models:** pairwise contrasts from the continuous model assume the dose-response relationship is perfectly linear and that all contrasts lie exactly on that line. This will not match CSR-reported pairwise results. The categorical model makes no linearity assumption — never derive pairwise comparisons from Model A.

**Failure modes to avoid:**
- Pairwise contrasts computed from the continuous model → wrong values, won't match CSR
- `at` argument omitted on the continuous model's `emmeans` call → LS means evaluated at the mean dose instead of actual dose levels
- `at` argument used on the categorical model's `emmeans` call → unnecessary, may cause warnings
- CIs taken from `emmeans()` directly instead of `contrast(..., 'revpairwise', infer = TRUE)` → CIs on group means, not on the differences
- Treatment variable not factored in Model B or used as numeric → both models end up testing the same thing
- Treatment variable factored in Model A → trend test is lost, no linear coefficient produced

## Examples

### Pattern 1: Trend Test Only (R)

```r
library(emmeans)

df <- read.csv("/path/to/dataset.csv")
df_ep <- df[df$PARAMCD == "<PARAMCD>" &
              df$AVISIT  == "<endpoint_visit>" &
              df$<population_flag> == "Y" &
              df$<analysis_flag>   == "Y", ]

cat("Unique PARAMCD:", unique(df_ep$PARAMCD), "
")
cat("Unique AVISIT:",  unique(df_ep$AVISIT),  "
")

model_a <- lm(<outcome> ~ <treatment_var_numeric> + <covariates>, data = df_ep)
summary(model_a)

dose_levels <- sort(unique(df_ep$<treatment_var_numeric>))
emm_cont <- emmeans(model_a, ~ <treatment_var_numeric>,
                    at = list(<treatment_var_numeric> = dose_levels))
summary(emm_cont)
confint(emm_cont)
```

### Pattern 1: Trend Test Only (SAS)

```sas
data ep;
  set <dataset>;
  where PARAMCD = "<PARAMCD>" and AVISIT = "<endpoint_visit>"
    and <population_flag> = "Y" and <analysis_flag> = "Y";
run;

proc freq data=ep; tables PARAMCD AVISIT; run;

proc mixed data=ep;
  class <categorical_covariates>;
  model <outcome> = <treatment_var_numeric> <covariates> <categorical_covariates> / solution;
  lsmeans <treatment_var_numeric> / cl;
run;
```

### Pattern 2: Trend Test + Pairwise Comparisons (R)

```r
library(emmeans)

df <- read.csv("/path/to/dataset.csv")
df_ep <- df[df$PARAMCD == "<PARAMCD>" &
              df$AVISIT  == "<endpoint_visit>" &
              df$<population_flag> == "Y" &
              df$<analysis_flag>   == "Y", ]

cat("Unique PARAMCD:", unique(df_ep$PARAMCD), "
")
cat("Unique AVISIT:",  unique(df_ep$AVISIT),  "
")

# Model A: continuous treatment — trend test only
model_a <- lm(<outcome> ~ <treatment_var_numeric> + <covariates>, data = df_ep)
summary(model_a)
dose_levels <- sort(unique(df_ep$<treatment_var_numeric>))
emm_cont <- emmeans(model_a, ~ <treatment_var_numeric>,
                    at = list(<treatment_var_numeric> = dose_levels))
confint(emm_cont)

# Model B: categorical treatment — pairwise comparisons only
# Use the existing categorical treatment variable (e.g., TRTP, ARM, ARMGRP, etc) if present
model_b <- lm(<outcome> ~ factor(<treatment_var_categorical>) + <covariates>, data = df_ep) 
summary(model_b)
emm_cat <- emmeans(model_b, ~ factor(<treatment_var_categorical>))

# If no categorical variable exists, factor the numeric treatment variable as a fallback:
# model_b <- lm(<outcome> ~ factor(<treatment_var_numeric>) + <covariates>, data = df_ep) 
# emm_cat <- emmeans(model_b, ~ factor(<treatment_var_numeric>))

# Pairwise comparisons and 95% CIs on differences
contrast(emm_cat, 'revpairwise', infer = TRUE)

```

### Pattern 2: Trend Test + Pairwise Comparisons (SAS)

```sas
data ep;
  set <dataset>;
  where PARAMCD = "<PARAMCD>" and AVISIT = "<endpoint_visit>"
    and <population_flag> = "Y" and <analysis_flag> = "Y";
run;

proc freq data=ep; tables PARAMCD AVISIT; run;

/* Model A: continuous treatment — trend test only */
proc mixed data=ep;
  class <categorical_covariates>;
  model <outcome> = <treatment_var_numeric> <covariates> / solution;
  lsmeans <treatment_var_numeric> / cl;
run;

/* Model B: categorical treatment — pairwise comparisons only */
proc mixed data=ep;
  class <treatment_var_categorical> <categorical_covariates>;
  model <outcome> = <treatment_var_categorical> <covariates> / solution;
  lsmeans <treatment_var_categorical> / diff cl;
run;
```

### Multiple Endpoints, Same Design 

Repeat the Pattern in separate, clearly labeled code blocks per endpoint — do not share model objects across endpoints.

#### For R:

```r
##### Multiple Endpoints, Same Design (R)
# Repeat the pattern in separate code blocks per endpoint using distinct variable names.

# --- Endpoint 1: <endpoint_name_1> (PARAMCD = "<PARAMCD1>") ---
df_ep1 <- df[df$PARAMCD == "<PARAMCD1>" & df$AVISIT == "<visit1>" & df$<population_flag> == "Y" & df$<analysis_flag> == "Y", ]
model_a_ep1 <- lm(<outcome> ~ <treatment_var_numeric> + <covariates>, data = df_ep1)
model_b_ep1 <- lm(<outcome> ~ factor(<treatment_var_categorical>) + <covariates>, data = df_ep1)

dose_levels1 <- sort(unique(df_ep1$<treatment_var_numeric>))
emm_cont_ep1 <- emmeans(model_a_ep1, ~ <treatment_var_numeric>, at = list(<treatment_var_numeric> = dose_levels1))
confint(emm_cont_ep1)

emm_cat_ep1 <- emmeans(model_b_ep1, ~ factor(<treatment_var_categorical>))
contrast(emm_cat_ep1, 'revpairwise', infer = TRUE)

# --- Endpoint 2: <endpoint_name_2> (PARAMCD = "<PARAMCD2>") ---
# Repeat the identical sequence using df_ep2, model_a_ep2, model_b_ep2, dose_levels2, emm_cont_ep2, emm_cat_ep2
```
#### For SAS:

```sas
/* Multiple Endpoints, same design: Repeat the pattern in separate DATA and PROC MIXED steps per endpoint */
/* Endpoint 1: data ep1; ... proc mixed data=ep1; ... */
/* Endpoint 2: data ep2; ... proc mixed data=ep2; ... */
```



## Self-Check (dose-response specific)

- [ ] Pairwise comparisons come from the categorical model (Model B) only, never the continuous model
- [ ] Continuous model uses treatment as numeric; categorical model uses `factor()` (R) or `CLASS` (SAS) 
- [ ] `at = list(...)` is used on the continuous model's `emmeans`; NOT used on the categorical model's
- [ ] 95% CIs on pairwise differences use `contrast(..., 'revpairwise', infer = TRUE)` 

Now, recheck this code against the references/REFERENCE.md file checklist before returning it to the user.
