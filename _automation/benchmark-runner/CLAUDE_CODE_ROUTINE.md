# Claude Code Benchmark Routine

This document provides instructions for setting up an automated benchmark routine in Claude Code to monitor skill performance.

## Prerequisites

- **Claude Code CLI** or **Gemini CLI** installed and authenticated.
- **GitHub CLI (`gh`)** authenticated with `repo` and `issue` permissions.
- **R Environment**: The routine will attempt to install R if missing, but having it pre-installed is recommended.

## Routine Setup

To enable a daily scheduled benchmark job, run the following command in your terminal from the repository root:

### For Claude Code
```bash
claude routine create "Daily Skill Benchmark" \
  --prompt "Requirement: Using R not Python to complete the work. Read the skill instructions from ./_automation/benchmark-runner/SKILL.md and follow every step exactly." \
  --schedule "0 2 * * *"
```

### For Gemini CLI
```bash
gemini routine create "Daily Skill Benchmark" \
  --prompt "Requirement: Using R not Python to complete the work. Read the skill instructions from ./_automation/benchmark-runner/SKILL.md and follow every step exactly." \
  --schedule "0 2 * * *"
```

This will create a routine that runs every day at 02:00 AM UTC.

## Prompt

The core instruction used by the routine is:

> Requirement: Using R not Python to complete the work. If required R and R package is not available, stop the rest work. 
> 
> Read the skill instructions from the file at the path below, then execute them exactly:
>  
> File: ./_automation/benchmark-runner/SKILL.md
> 
> If that path is not accessible, try the workspace mount path or fetch from GitHub:
> https://github.com/RConsortium/pharma_skills/blob/main/_automation/benchmark-runner/SKILL.md
> 
> Follow every step in the SKILL.md. The skill is self-contained — it describes how to discover evals, run sub-agents, score results, and post to GitHub issues.

## Environment Variables

Ensure the following environment variables are available in the shell where the agent is running:

- `GITHUB_TOKEN`: Required if `gh auth status` is not configured.
- `PHARMA_SKILLS_RUNNER_ID`: (Optional) A unique string to identify this runner in distributed selection (e.g., your name or machine ID).

## Allowed Domains

The routine requires access to the following domains for R package installation and GitHub interactions. Ensure these are allowed in your `.claude/settings.json` or provided during the session:

```text
cran.r-project.org
*.r-project.org
cloud.r-project.org
packagemanager.posit.co
rspm-sync.rstudio.com
*.posit.co
bioconductor.org
*.bioconductor.org
github.com
*.githubusercontent.com
ppa.launchpadcontent.net
```

## How it Works

1. **Pre-flight**: Checks for R and required statistical packages via `setup_r_env.sh`.
2. **Discovery**: Runs the dispatcher to find the next pending evaluation for the current model.
3. **Execution**: Launches two isolated sub-agents in parallel (Agent A with skill, Agent B without).
4. **Scoring**: Scores the anonymized outputs against rubric assertions using a fresh scoring session.
5. **Reporting**: Packages artifacts into a zip, uploads to GitHub Releases, and posts a scorecard as a comment on the original issue.

## Troubleshooting

- **Permissions**: If the routine fails to post comments, verify `gh auth status` or your `GITHUB_TOKEN` scopes.
- **R Packages**: If R package installation fails, check the "Allowed Domains" list.
- **Interruption**: If the routine is interrupted by turn limits, the dispatcher will attempt to pick up the same evaluation on the next run if it wasn't marked as completed.
