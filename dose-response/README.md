# Dose-Response Skill
A skill that generates R code for dose-response analyses (ANCOVA or ANOVA) where treatment is a continuous dose variable. Covers linear trend testing and pairwise group comparisons with 95% confidence intervals.

## What It Does
Given a dose-response analysis request, this skill:
1. **Identifies the analysis pattern** — trend test only, or trend test + pairwise comparisons
2. **Enforces the two-model requirement** — generates separate models for the linear trend test (continuous treatment) and pairwise comparisons (categorical treatment), preventing the common failure of deriving pairwise contrasts from the continuous model
3. **Produces correct emmeans calls** — applies `at = list(...)` on the continuous model and `contrast(..., 'revpairwise', infer = TRUE)` for 95% CIs on pairwise differences
4. **Supports multiple endpoints** — generates separate code blocks per endpoint with distinct model objects

### Supported Patterns
| Pattern | Use When |
| ------ | ------ |
| Pattern 1 | Trend test only |
| Pattern 2 | Trend test + pairwise comparisons |
| Pattern 2 variant | Multiple endpoints, same design |

## Recommendations
To use this skill with trial submission documents in PDF, it is recommended to use a Python virtual environment with a pdf processor such as `pypdfium2` that conserves table formatting (see environment instructions in [references/submission-orientation.md](references/submission-orientation.md)).

## Usage
Invoke the skill by describing the analysis naturally:
- *"Please generate R code to perform the primary ADAS-Cog analysis specified in the SAP, including pairwise treatment comparisons and their 95% CIs. The submission files can be found in submissions/pilot01 folder."*
- *"Please generate R code to perform the co-primary CIBIC+ analysis specified in the SAP, including pairwise treatment comparisons and their 95% CIs. The submission files can be found in submissions/pilot01 folder."*
- *"Please generate R code to perform the primary dose-response ADAS-Cog analysis specified in the SAP, including pairwise treatment comparisons and their 95% CIs. The submission files can be found in submissions/pilot01 folder."*
    - We have found that the skill sometimes performs better when "trigger" key words are not used in the prompt. This may be due to the agent reading through more of the submission documents rather than immediately resorting to target checks within the submission.

The skill will identify the correct pattern and generate code using variable names, dose levels, covariates, and population flags extracted from the submission documents via [`references/submission-orientation.md`](references/submission-orientation.md).

## Key Design Principles
* **Two-model requirement**: Pairwise comparisons always require a separate categorical model — never derived from the continuous trend-test model. This is the most common silent failure in dose-response code generation.
* **emmeans correctness**: `at = list(...)` is required on the continuous model; `contrast(..., 'revpairwise', infer = TRUE)` produces CIs on differences, not on group means.
* **Document-driven** : The skill guides the agent through extracting exact model specifications, dose levels, covariates, and variable names directly from submission documents (SAP, ADRG, define.xml) via [references/submission-orientation.md](references/submission-orientation.md) before generating any R code.


## Skill File Reference
| File | Purpose |
| ------ | ------ |
| [SKILL.md](SKILL.md) | Main entry point — scope, workflow steps, pattern examples, self-check |
| [DESIGN.md](DESIGN.md) | Skill scope documentation |
| [references/submission-orientation.md](references/submission-orientation.md) | Required workflow for extracting endpoints and variable mappings from SAP, ADRG, and `define.xml` |
| [references/REFERENCE.md](references/REFERENCE.md) | General code generation rules and self-check checklist |
| [references/examples.md](references/examples.md) | R code templates for the agent|

**Why code template patterns are in a separate reference file**:
Code template patterns are separated from the main skill instructions to prevent agents from skipping the required document extraction workflow by jumping directly to code generation, resulting in incorrect variable mappings. Progressive disclosure of code patterns enforces the structured workflow so that code that adheres to the submission context.


### Tested On
* CDISC pilot01 submission
* Model: Gemma4-31B-it within Cline

### License
[MIT](LICENSE)