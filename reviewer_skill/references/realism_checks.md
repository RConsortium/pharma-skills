# Data Realism Checks

Read this file whenever subject-level data (ADaM or SDTM) is provided. These checks assess whether the data exhibits the natural variation, correlation structure, and operational patterns expected from a real clinical trial.

Reviewer mindset: "Does this data look like it came from real patients in real clinics, or does it show hallmarks of synthetic generation, data fabrication, or systematic operational failure?"

**Why this matters:** Simulated, fabricated, or heavily manipulated data can pass all standard reproducibility and traceability checks while still being fundamentally unreliable. Regulatory agencies (FDA, EMA) have encountered fraudulent trial data that was internally consistent but lacked the natural messiness of real clinical operations. These checks provide a complementary lens.

**Output:** Report an overall **realism score (1–10)** where 10 = indistinguishable from real trial data, 1 = obviously synthetic. Provide a structured table of realistic vs unrealistic features with specific evidence.

---

## 5.1 Temporal pattern realism

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Visit timing variation | High | Compute actual visit day minus nominal visit day across all subjects/visits | Natural jitter ±3–7 days, some larger deviations, occasional missed windows | All visits land on exact nominal day (0 variance); or perfectly uniform spacing |
| AE onset day distribution | High | Examine ASTDY distribution for all AEs and by PT category | Continuous distribution across all calendar days; no grid artifacts | All AE onsets on multiples of 7, or restricted to a small set of values |
| GI AE temporal front-loading | High | For nausea/vomiting/diarrhoea in GLP-1, GI-class, or titrated drugs: proportion of GI AEs in first 4 weeks vs later | 40–60% of GI AEs onset in first 2–4 weeks (especially with dose escalation) | Uniform distribution of GI AE onset across the treatment period |
| Dropout timing distribution | High | Examine treatment duration for discontinued subjects | Dropout on various days, some between visits, some at visits, distributed across treatment period | All dropouts locked to exact visit days only; no inter-visit dropout |
| Seasonal/calendar variation | Low | Check enrollment dates and visit dates for calendar-day patterns | Various days of week for visits; enrollment spread over months | All visits on same weekday; enrollment on identical calendar pattern |

**How to check:** Compute `actual_day - nominal_day` for all visits. If SD = 0, the data is gridded. For AE onset, check the number of unique ASTDY values relative to the maximum study day — real data should use most integer days; synthetic data often restricts to visit-day multiples.

---

## 5.2 Baseline correlation structure

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Within-system correlations | High | Identify physiologically linked baseline continuous variables and check pairwise correlations | Moderate-to-strong correlations (r ≈ 0.2–0.7) between variables from the same organ system | Near-zero correlations (r < 0.1) between variables that should be physiologically linked |
| Age–comorbidity correlation | Medium | Check if older subjects have higher disease-burden markers | Modest positive correlation (r ≈ 0.1–0.3) between age and severity/comorbidity measures | Zero or negative age-physiology correlations where positive expected |
| Sex differences in baseline | Medium | Compare distributions by sex for sex-dimorphic variables | Males typically taller, heavier; sex-specific lab ranges respected | Identical distributions for males and females on dimorphic variables |
| Multivariate structure | Medium | PCA or eigenvalue decomposition of baseline matrix (if ≥5 continuous variables available) | First few PCs explain 40–60% of variance; interpretable structure | All PCs explain equal variance (spherical — variables generated independently) |

**How to apply (TA-independent):**

Identify whatever continuous baseline variables exist in the data and check for physiologically expected correlations. The specific pairs depend on the therapeutic area:

- **Any TA with vitals:** SBP–DBP (expect r ≈ 0.3–0.5)
- **Any TA with height/weight:** Weight–BMI (expect r ≈ 0.7–0.9), Height–Weight (r ≈ 0.4–0.6)
- **Metabolic/endocrine:** HbA1c–Glucose, Weight–Insulin, BMI–Triglycerides, BMI–CRP
- **Thyroid:** TSH–FT4 (expect negative r ≈ -0.1 to -0.4)
- **Hepatic:** ALT–AST (expect r ≈ 0.5–0.8)
- **Renal:** eGFR–Creatinine (expect strong negative r)
- **Hematology:** Hgb–Hct (expect r > 0.9)

If fewer than 3 continuous baseline variables are available, skip PCA and focus on pairwise checks only. Flag r < 0.05 for any pair that should be physiologically correlated.

---

## 5.3 Physiological plausibility

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Baseline value ranges | High | Check min/max against known physiological limits | All values within 3–4 SD of population means; rare outliers present but plausible | Values outside physiological possibility (negative BP, BMI < 18 in obesity trial, glucose > 50 mmol/L) |
| Unit consistency | High | Verify units match expected magnitudes | Fasting insulin 5–50 mU/L (typical obese non-diabetic); HbA1c 30–48 mmol/mol (non-diabetic) or 5–7% (NGSP) | Values suggesting wrong unit (e.g., insulin >100 suggesting pmol/L reported as mU/L) |
| On-treatment trajectory magnitude | High | Check if endpoint changes are clinically plausible | Weight loss 5–25% over 48–68 weeks for GLP-1; HbA1c drops 0.5–2.0% in non-diabetics | Weight loss >40% (beyond bariatric surgery); HbA1c drop >5% in non-diabetics |
| Impossible recovery patterns | Medium | After treatment discontinuation, check if values snap back instantly | Gradual return toward baseline over weeks/months | Instant return to exact baseline value at first post-discontinuation visit |
| Extreme outlier frequency | Medium | Count subjects with values > 4 SD from mean | 0–2% of values beyond 4 SD; present but rare | Either zero outliers (too clean) or >5% extreme outliers (generation error) |
| Within-subject trajectory smoothness | Medium | Check longitudinal trajectories for physiological smoothness | Modest visit-to-visit variation (biological + measurement noise); no identical consecutive values (except stable parameters) | Perfect monotone curves with zero noise; or chaotic jumps between visits |

---

## 5.4 Site and geographic effects

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Between-site baseline variation | High | ANOVA or Kruskal-Wallis for baseline continuous variables across sites | Significant (p < 0.05) differences for some variables; modest ICC (0.01–0.10) | All sites have identical distributions (ANOVA p > 0.90 for all variables) |
| Site-level enrollment patterns | Medium | Check N per site, enrollment timing | Some sites enroll faster/slower; staggered start dates | All sites enroll same N on same dates |
| Geographic/ethnic consistency | Medium | Country/region should correlate with race, BMI distribution, lab normal ranges | Regional differences in BMI, race distribution, metabolic parameters | Identical race/baseline distributions across countries on different continents |
| Site-level outcome variation | Low | Check treatment effect heterogeneity across sites | Some natural variation in response by site (random effects) | Identical treatment response at every site |

---

## 5.5 Dropout and missing data realism

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Dropout timing distribution | High | Histogram of time-to-discontinuation | Spread across treatment period; some early, some later; matches known patterns for drug class | All dropout at exact same time points; or dropout only at endpoint |
| Informative missingness | High | Compare baseline characteristics of completers vs dropouts | Dropouts often have higher baseline severity, lower socioeconomic indicators, more AEs | Dropouts completely random (identical baselines); or perfectly predicted by single variable |
| Reason-AE consistency | High | Subjects with DCSREAS='Adverse Event' should have ≥1 AE record | 100% have ≥1 AE | Any subject discontinued for AE with no AE records |
| Withdrawal-by-subject pattern | Medium | Subjects withdrawing consent need NOT have AEs, but may correlate with early non-response or side effects | Mix of reasons; not all early, not all late | All consent withdrawals on exact same study day |
| Missing data monotonicity | Medium | Once a subject is missing, they should stay missing (no data after dropout) | Strictly monotone for efficacy; some safety follow-up after treatment discontinuation acceptable | Non-monotone missingness without explanation (intermittent missing visits followed by returns) |
| Differential dropout by arm | High | More dropout in arms with more side effects or less efficacy | Plausible direction (GI drugs: more early active-arm dropout; or more placebo dropout if drug works well) | Identical dropout rates across all arms including placebo |

---

## 5.6 AE pattern realism

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| AE onset relative to treatment start | High | Distribution of time from first dose to AE onset | GI/injection site: front-loaded (Weeks 1–4); infections: distributed; skin: delayed (Weeks 4–12) | All AE categories have identical onset distribution |
| Duration distribution | Medium | AE duration (AENDT - ASTDT) | Varied: some acute (days), some chronic (weeks/months); some ongoing at end of study | All AEs have identical duration; or all end on exact same relative day |
| Dose-response in AE rates | High | Higher doses → more drug-class AEs | Monotone or near-monotone dose-response for expected AEs | Random scatter with no dose-response for drug-class AEs |
| Severity distribution | Medium | Most AEs mild/moderate; few severe | 60–70% mild, 20–30% moderate, 5–15% severe (varies by drug class) | All same severity; or unrealistic severity split |
| Multiple AEs per subject | Medium | Some subjects have multiple AE terms | Correlation between related GI AEs (nausea + vomiting often co-occur) | Each subject has exactly 1 AE; or AE terms assigned independently |
| Placebo AE rates | High | Placebo should still have background AE rates | Common AEs (headache, nasopharyngitis) present in placebo at 5–15%; GI background rate 5–10% | Zero AEs in placebo; or placebo rates identical to high-dose active |

**Drug-class-specific AE onset timing expectations:**

For immune-oncology (checkpoint inhibitors: anti-PD-1/PD-L1, anti-CTLA-4):

| AE category | Expected onset timing | Flag if |
|---|---|---|
| Skin (rash, pruritus, vitiligo) | Early: median 2–6 weeks (often first irAE to appear) | Median onset > 16 weeks |
| GI (diarrhea, colitis) | Bimodal: mild GI 2–6 weeks; colitis/severe 6–16 weeks | Uniform distribution or all onset > 20 weeks |
| Hepatitis (ALT/AST elevation) | Intermediate: median 6–12 weeks | Onset < 2 weeks or > 24 weeks for majority |
| Thyroid (hypothyroidism, hyperthyroidism) | Delayed: median 8–16 weeks; hyperthyroidism often precedes hypothyroidism | Median onset < 4 weeks (too early for thyroid autoimmunity) |
| Pneumonitis | Variable/late: median 8–24 weeks; can occur anytime | All cases in first 4 weeks |
| Fatigue | Throughout: relatively uniform across treatment period | Strongly clustered in single time window |
| Arthralgia/myalgia | Intermediate to late: median 8–20 weeks | All onset in first 2 weeks |
| Infusion reactions | Immediate: day of or within 24h of infusion (onset = visit day) | Onset days between infusions |

For GLP-1 receptor agonists (semaglutide, tirzepatide, liraglutide):

| AE category | Expected onset timing | Flag if |
|---|---|---|
| GI (nausea, vomiting, diarrhea) | Front-loaded: 40–60% in first 4 weeks, especially during dose escalation | Uniform distribution across study |
| Injection site reactions | Early: first 2–4 weeks, diminishing | Late-onset only |
| Pancreatitis | Any time, no strong temporal pattern | Only in first week |
| Cholelithiasis | Late: typically after significant weight loss (12+ weeks) | All cases in first 4 weeks |

For TKIs (tyrosine kinase inhibitors):

| AE category | Expected onset timing | Flag if |
|---|---|---|
| Diarrhea | Early: first 2–4 weeks | Only late-onset |
| Hypertension | Early to intermediate: 2–8 weeks | Onset > 20 weeks for majority |
| Hand-foot syndrome | Intermediate: 4–12 weeks | All in first week |
| Fatigue | Throughout, may worsen with prolonged exposure | Uniform or improving over time |

---

## 5.7 Longitudinal endpoint realism

Apply these checks when repeated continuous measurements are available (e.g., labs over time, PRO scores, vital signs). Skip this section for pure time-to-event data without longitudinal continuous endpoints.

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Trajectory shape | High | Continuous endpoints should show clinically plausible change patterns over time | Non-linear: rapid early change then plateau (most drug effects); or gradual monotone (degenerative diseases) | Perfectly linear; step-function jumps; or identical curves for all subjects |
| Within-subject noise | High | Visit-to-visit variation around the trend (biological + measurement variability) | Modest noise (CV 2–10% depending on parameter); no two consecutive identical values for variable parameters | Zero noise (monotone smooth curve); or chaotic >20% jumps between visits |
| Treatment-effect heterogeneity | High | Subjects within the same arm should show varied responses | Meaningful SD of individual responses; some non-responders in active arm, some placebo responders | All subjects in an arm have identical response; or SD = 0 |
| Imputation/extrapolation plausibility | Medium | If imputed values exist (DTYPE populated), they should be plausible | Imputed values within the range of observed values; imputed trajectories drift toward natural history | All imputed values identical; or imputed values more extreme than any observed |
| Cross-endpoint correlation | Medium | Related endpoints should correlate (e.g., weight and metabolic markers; BP and CV events; tumor burden and survival) | Moderate correlations (r ≈ 0.2–0.6) between mechanistically linked endpoints | Near-perfect correlation (r > 0.95, suggesting deterministic function) or zero correlation between linked endpoints |

---

## 5.8 Operational patterns

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Enrollment duration | Low | Time from first to last subject enrolled | Multi-site trials typically enroll over 6–18 months | All subjects enrolled on same day |
| Visit window compliance | Medium | Proportion of visits within protocol-specified windows | 85–95% within window; 5–15% outside but still collected | 100% perfectly on-window (unrealistic operational perfection) |
| Data completeness by visit | Medium | Gradual decrease in completeness at later visits | 90–95% at early visits, 70–85% at late visits (depending on dropout) | Exactly same N at all visits until sudden drop to 0 |
| Lab sample timing | Low | For fasting labs: variation in collection time | Some variation ±1–2 hours in sample timing | All samples at exact same time |
| Weekend/holiday patterns | Low | Fewer visits on weekends, around holidays | Visit dates cluster on weekdays | Uniform distribution including weekends |

---

## 5.9 Data integrity signals

| Check | Priority | Logic | Realistic | Unrealistic |
|---|---:|---|---|---|
| Digit preference | Medium | Last-digit distribution of continuous measurements (weight, BP, lab values) | Some digit preference (0, 5 more common in manually recorded BP) | Perfect uniform digit distribution (synthetic); or extreme digit preference (fabricated) |
| Duplicated records | High | Identical rows or near-identical patterns across subjects | Rare; if present, represents data entry error | Many subjects with identical lab trajectories or identical AE patterns |
| Benford's Law for first digits | Low | First-digit distribution of lab values, weights | Roughly follows Benford's Law for naturally occurring data | Uniform first-digit distribution |
| Rounding patterns | Medium | Precision of reported values | Weight to 0.1 kg; BP to nearest 2 mmHg (manual); lab values to assay precision | All values rounded to integers; or excessive precision (10+ decimal places) |
| Cross-subject independence | High | Are subject-level data truly independent? | Unique trajectories per subject; within-site correlations for environmental factors only | Multiple subjects with identical value sequences (copy-paste fabrication) |

---

## Realism scoring rubric

| Score | Meaning | Key signals |
|---:|---|---|
| 9–10 | Indistinguishable from real trial data | Natural visit jitter, realistic correlations, site effects, clinical AE patterns, digit preference |
| 7–8 | Realistic with minor artifacts | Most patterns realistic; 1–2 small tells (e.g., slightly too-perfect visit timing) |
| 5–6 | Recognizably synthetic but usable for methods development | Correct high-level patterns (dose-response, dropout direction); but missing natural variation |
| 3–4 | Obviously synthetic | Gridded timing, independent baselines, no site effects, deterministic trajectories |
| 1–2 | Implausible | Physiologically impossible values, violated temporal ordering, or identical subjects |

---

## Report format for realism assessment

```
## Data realism assessment

**Overall realism score: X/10**

### Realistic features
| Feature | Evidence |
|---|---|
| [feature] | [specific values/statistics] |

### Unrealistic features
| Feature | Evidence | Severity | Recommendation |
|---|---|---|---|
| [feature] | [specific values/statistics] | High/Medium/Low | [how to improve] |

### Implications
[What the realism issues mean for the review: can we trust the data for regulatory purposes?
If synthetic: is this adequate for its stated purpose (methods development, training, etc.)?]
```

**Interpretation guidance:**
- **Real submission data with score < 7:** Flag potential data integrity concerns for regulatory attention. Site-level fabrication (e.g., too-uniform data from one site) should be investigated.
- **Known simulated data:** The realism score guides whether the simulation is adequate for its stated purpose (e.g., methods development, training, software validation).
- **Score 3–4 for simulated data:** Acceptable for testing programming logic but not for validating statistical properties that depend on realistic correlation structure.

---

## Known-simulation interpretation mode

When the data is explicitly simulated (stated by the user, evident from file naming conventions like `ipd_sim`, or revealed by the presence of calibration/target files), apply these adjustments:

**Severity adjustment for realism findings:**
- Realism issues that would be **High** for real data (suggesting fabrication/fraud) become **Medium** for known simulations (improvement recommendation).
- Realism issues that would be **Medium** for real data become **Low** for known simulations.
- The `overall_result` should **never** be FAIL solely due to realism issues in known simulated data.

**Finding classification:**
- Separate findings into two categories in the report: **Data integrity findings** (programming errors, traceability gaps, logical inconsistencies — issues that exist regardless of whether data is real or simulated) and **Simulation realism findings** (features that reveal synthetic generation patterns — improvement opportunities for the simulation).
- Data integrity findings use standard severity. Simulation realism findings use adjusted (downgraded) severity.

**Interpretation language:**
- For real data: "This pattern raises concerns about data integrity / potential fabrication at site X."
- For simulated data: "This pattern reveals a simulation simplification. Recommendation for improvement: [specific suggestion]."

**What still counts as High severity in simulated data:**
- Programming/logic errors that produce incorrect analysis results (e.g., wrong counts, broken traceability between DS and ADAE)
- Inconsistencies that would mislead a user relying on this data for methods development
- Issues where the TLF reports a number that cannot be reproduced from the underlying data
