## Key Rules

**The Two-Model Requirement**

A dose-response analysis with pairwise comparisons always requires two separate models. This is not optional.

- **Model A — continuous treatment (trend test):** treatment variable enters as numeric. Tests for a linear trend across dose levels. Produces the treatment coefficient, SE, and p-value for trend. Use `emmeans` with `at = list(treatment_var = c(dose levels))` to get LS means at each dose level.
- **Model B — categorical treatment (pairwise comparisons):** treatment variable coded as a factor. Same outcome, covariates, population filter, and visit filter as Model A. Produces pairwise LS mean differences, 95% CIs, and p-values. Call `emmeans` without the `at` argument; use `contrast(..., 'revpairwise', infer = TRUE)` for 95% CIs on the pairwise differences.

**Why two models:** pairwise contrasts from the continuous model assume the dose-response relationship is perfectly linear and that all contrasts lie exactly on that line. This will not match CSR-reported pairwise results. The categorical model makes no linearity assumption — never derive pairwise comparisons from Model A.

**Failure modes to avoid:**
- Pairwise contrasts computed from the continuous model → wrong values
- `at` argument omitted on the continuous model's `emmeans` call → LS means evaluated at the mean dose instead of actual dose levels
- `at` argument used on the categorical model's `emmeans` call → unnecessary, may cause warnings
- CIs taken from `emmeans()` directly instead of `contrast(..., 'revpairwise', infer = TRUE)` → CIs on group means, not on the differences
- Treatment variable not factored in Model B or used as numeric → both models end up testing the same thing
- Treatment variable factored in Model A → trend test is lost, no linear coefficient produced

## Examples

### Pattern 1: Trend Test Only 

```r
library(emmeans)

df <- read.csv("/path/to/dataset.csv")
df_ep <- df[df$PARAMCD == "<PARAMCD>" &
              df$AVISIT  == "<endpoint_visit>" &
              df$<population_flag> == "Y" &
              df$<analysis_flag>   == "Y", ]

cat("Unique PARAMCD:", unique(df_ep$PARAMCD), "\n")
cat("Unique AVISIT:",  unique(df_ep$AVISIT),  "\n")

model_a <- lm(<outcome> ~ <treatment_var_numeric> + <covariates>, data = df_ep)
summary(model_a)

dose_levels <- sort(unique(df_ep$<treatment_var_numeric>))
emm_cont <- emmeans(model_a, ~ <treatment_var_numeric>,
                    at = list(<treatment_var_numeric> = dose_levels))
summary(emm_cont)
confint(emm_cont)
```


### Pattern 2: Trend Test + Pairwise Comparisons 

```r
library(emmeans)

df <- read.csv("/path/to/dataset.csv")
df_ep <- df[df$PARAMCD == "<PARAMCD>" &
              df$AVISIT  == "<endpoint_visit>" &
              df$<population_flag> == "Y" &
              df$<analysis_flag>   == "Y", ]

cat("Unique PARAMCD:", unique(df_ep$PARAMCD), "\n")
cat("Unique AVISIT:",  unique(df_ep$AVISIT),  "\n")

# Model A: continuous treatment — trend test only
model_a <- lm(<outcome> ~ <treatment_var_numeric> + <covariates>, data = df_ep)
summary(model_a)
dose_levels <- sort(unique(df_ep$<treatment_var_numeric>))
emm_cont <- emmeans(model_a, ~ <treatment_var_numeric>,
                    at = list(<treatment_var_numeric> = dose_levels))
confint(emm_cont)

# Model B: categorical treatment — pairwise comparisons only
# Use the _existing_ categorical treatment variable (e.g., TRTP, ARM, ARMGRP, etc) if present, as follows:
model_b <- lm(<outcome> ~ factor(<treatment_var_categorical>) + <covariates>, data = df_ep) 
summary(model_b)
emm_cat <- emmeans(model_b, ~ factor(<treatment_var_categorical>))

# ONLY if no categorical variable exists, factor the numeric treatment variable as a fallback:
# model_b <- lm(<outcome> ~ factor(<treatment_var_numeric>) + <covariates>, data = df_ep) 
# emm_cat <- emmeans(model_b, ~ factor(<treatment_var_numeric>))

# Pairwise comparisons and 95% CIs on differences
contrast(emm_cat, 'revpairwise', infer = TRUE)

```


### Multiple Endpoints, Same Design 

Repeat the Pattern in separate, clearly labeled code blocks per endpoint — do not share model objects across endpoints.

```r

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



## Self-Check (dose-response specific)

- [ ] Pairwise comparisons come from the categorical model (Model B) only, never the continuous model
- [ ] Continuous model uses treatment as numeric; categorical model uses `factor()`  
- [ ] Categorical model uses the character treatment variable (e.g., TRTP, ARM, etc), not factor() applied to the numeric version (e.g., factor(TRTPN))
- [ ] `at = list(...)` is used on the continuous model's `emmeans`, NOT used on the categorical model's `emmeans`
- [ ] 95% CIs on pairwise differences use `contrast(..., 'revpairwise', infer = TRUE)` 

Now, return to the TASKSs and follow the remaining rules in **TASK 4**.