## Dose-Response Skill
A skill for AI coding agents (Cline, Claude Code, or compatible) that generates correct R or SAS code for dose-response analyses (ANCOVA or ANOVA) where treatment is a continuous dose variable. Covers linear trend testing and pairwise group comparisons with 95% confidence intervals.

### What It Does
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

### Requirements
**To use this skill with trial submission documents in PDF:**
* Python virtual environment with `pypdfium2` (If you use a different PDF processor, edit `CLAUDE.md` for Claude Code or `.clinerules/pdf-reading.md` for Cline).

### Installation - Cline VSCode extension
Download the `dose-response/` skill package. Copy the `dose-response/` folder into your workspace's `.agents/skills/` directory. Copy the `.clinerules/`, `references/`, and `submissions/` folders into your **workspace root**.


```bash
# In bash, run these commands from your workspace root

# 1. Create the skill directory and copy the skill package
mkdir -p .agents/skills/
cp -r dose-response .agents/skills/

# 2. Copy root workspace dependencies (check for existing files first!)
cp -r dose-response/.clinerules ./
cp -r dose-response/references ./
cp -r dose-response/submissions ./
```
This will give the following structure:

```
your-workspace/
├── .clinerules/
│   ├── workflow.md
│   ├── pdf-reading.md
│   └── python-environment.md
├── .agents/
│   └── skills/
│       └── dose-response/
│           ├── SKILL.md
│           ├── DESIGN.md
│           ├── LICENSE
│           ├── README.md
│           └── CLAUDE.md
├── references/
│   ├── submission-orientation.md
│   └── REFERENCE.md
└── submissions/
    └── pilot01/
        ├── SAP.pdf
        ├── ADRG.pdf
        ├── define.xml
        └── *.csv
```

Create a Python virtual environment for PDF reading (If you prefer a different pdf processor, change the instructions in `.clinerules/pdf-reading.md`):
```bash
python -m venv .venv
.venv/bin/pip install pypdfium2 
```

### Installation - Claude Code
Download the `dose-response/` skill package. Copy the `dose-response/` folder into your project's `.claude/skills/` directory. Copy `CLAUDE.md`, `references/`, and `submissions/` folders into your **project root**.

```bash
# In bash, run these commands from your project root:

# 1. Create the skill directory and copy the skill package
mkdir -p .claude/skills/
cp -r dose-response .claude/skills/

# 2. Copy root workspace dependencies (check for existing files first!)
cp dose-response/CLAUDE.md ./
cp -r dose-response/references ./
cp -r dose-response/submissions ./
```

This will give the following structure:

```
your-project/
├── CLAUDE.md
├── .claude/
│   └── skills/
│       └── dose-response/
│           ├── SKILL.md
│           ├── DESIGN.md
│           ├── LICENSE
│           ├── README.md
│           └── CLAUDE.md
├── references/
│   ├── submission-orientation.md
│   └── REFERENCE.md
└── submissions/
    └── pilot01/
        ├── SAP.pdf
        ├── ADRG.pdf
        ├── define.xml
        └── *.csv
```

Create a Python virtual environment for PDF reading (If you prefer a different pdf processor, change the instructions in `CLAUDE.md`):
```bash
python -m venv .venv
.venv/bin/pip install pypdfium2 
```

### Usage
Invoke the skill in Claude Code or Cline by describing the analysis naturally:
- *"Please generate R code to perform the primary ADAS-Cog analysis specified in the SAP, including pairwise treatment comparisons and their 95% CIs. The submission files can be found in `submissions/pilot01` folder."*
- *"Please generate R code to perform the co-primary CIBIC+ analysis specified in the SAP, including pairwise treatment comparisons and their 95% CIs. The submission files can be found in `submissions/pilot01` folder."*

The skill will identify the correct pattern and generate code using variable names, dose levels, covariates, and population flags extracted from the submission documents via `references/submission-orientation.md`.

### Key Design Principles
* **Two-model requirement**: Pairwise comparisons always require a separate categorical model — never derived from the continuous trend-test model. This is the most common silent failure in dose-response code generation.
* **emmeans correctness**: `at = list(...)` is required on the continuous model; `contrast(..., 'revpairwise', infer = TRUE)` produces CIs on differences, not on group means.
* **Context-driven**: The skill does not perform endpoint extraction or variable mapping — it assumes the calling agent has already resolved variable names, dose levels, covariates, and file paths from the submission documents via `references/submission-orientation.md`.
* **SAP-first**: Reading the SAP is treated as a requirement. The agent must read the SAP model specification before writing any code — general statistical knowledge is not a substitute.

### Skill File Reference
| File | Purpose |
| ------ | ------ |
| `SKILL.md` | Main entry point — scope, workflow steps, pattern examples, self-check |
| `DESIGN.md` | Skill scope documentation |
| `references/submission-orientation.md` | Required workflow for extracting endpoints and variable mappings from SAP, ADRG, and `define.xml` |
| `references/REFERENCE.md` | General code generation rules and self-check checklist |

### Tested On
* CDISC pilot01 submission
* Model: Gemma4-31B-it
* ADaM datasets (Patterns 1/2)

### License
[MIT](LICENSE)