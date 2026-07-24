# Pharma Skills

A collection of agent skills for pharmaceutical R&D.

## Disclaimer

This is an open, community-contributed catalog built as part of R Consortium Submissions Working Group Pilot 7. Skills go through community [benchmarking](LIFECYCLE.md) and carry no warranty or endorsement from the R Consortium, the BBSW AI committee, or any contributor's employer.

These skills produce artifacts that can feed into clinical trial design and regulatory workflows (trial designs, ADaM datasets, simulated data, statistical review). Treat all outputs as a drafting aid, not a validated deliverable — LLM outputs can be wrong or inconsistent between runs, so always independently verify them against your own QC process before they inform any regulatory, clinical, safety, or GxP-regulated activity. You're responsible for that verification and for complying with your organization's policies. Skills may also bundle scripts that execute in your environment, so review a skill's contents before installing and only supply data you're permitted to use. Everything here is MIT-licensed (see [License](#license)) and provided as-is.

## Skills

| Skill | Description |
|-------|-------------|
| [group-sequential-design](group-sequential-design/) | Design group sequential clinical trials for survival endpoints (OS, PFS, DFS) with interim analyses, spending functions, multiplicity, and event/enrollment prediction |
| [clinical-trial-simulation](clinical-trial-simulation/) | Design and simulate clinical trials using the TrialSimulator R package and produce a QC-ready build-order-spine report. Design-agnostic: composes from independent building blocks (endpoints, arms, milestones, regimens) rather than following a fixed catalog of design templates. |
| [admiral/admiral-adsl](admiral/admiral-adsl/) | Derive ADaM Subject-Level Analysis Datasets (ADSL) from SDTM domains using the {admiral} R package. Encodes the workflow, function selection logic, and CDISC conventions for QC-ready, submission-traceable R code. |
| [admiral/admiral-bds](admiral/admiral-bds/) | Derive ADaM BDS findings datasets (ADVS, ADLB) from SDTM VS/LB domains. Covers parameter assignment, baseline flagging, change from baseline, visit windowing, and ADLB normal range derivations. |
| [clinical-trial-ipd-sim](clinical-trial-ipd-sim/) | Generate synthetic IPD, source CRFs, SDTM, ADaM, and exports for registered clinical trials using an R/pharmaverse g-formula causal-DAG workflow calibrated to posted protocol and results. |
| [statistical-reviewer](statistical-reviewer/) | Simulate an independent statistical reviewer auditing a clinical trial submission package (SDTM, ADaM, TLF, SAP, CSR) — reproducing endpoints, tracing results across data layers, flagging population inconsistencies, and assessing data realism. |

## Installation

### Using `npx skills add` (Any Agent)

Install skills from this repository into any supported coding agent (Claude Code, Codex, Cursor, Cline, Copilot, and [many more](https://github.com/vercel-labs/skills)) using the `npx skills add` CLI:

```bash
# List available skills without installing
npx skills add RConsortium/pharma-skills --list

# Install skills via an interactive menu
npx skills add RConsortium/pharma-skills --all

# Install specific skills by name
npx skills add RConsortium/pharma-skills --skill group-sequential-design --skill admiral-adsl

# Install to Claude Code only, globally
npx skills add RConsortium/pharma-skills --agent claude-code --global
```

### Conversational / CLI (Any Agent)

Ask your agent to enable a skill directly from this repo, without cloning it yourself:

> enable "group-sequential-design" skill from https://github.com/RConsortium/pharma-skills

### Manual Installation (Claude Code, Cursor, Windsurf, Copilot, etc.)

1. Clone this repository locally or add it as a git submodule:

   ```bash
   git clone https://github.com/RConsortium/pharma-skills.git
   ```

2. Copy or symlink the skill(s) you need into your project or agent's skills directory. Symlinking keeps the skill up to date with `git pull`:

   ```bash
   # Copy a single skill (e.g. for Claude Code)
   cp -r pharma-skills/group-sequential-design ~/.config/claude-code/skills/

   # Or symlink instead of copying
   ln -s "$(pwd)/pharma-skills/group-sequential-design" ~/.config/claude-code/skills/group-sequential-design
   ```

3. Or manually reference the skill in your configuration files (like `.cursorrules`, `AGENTS.md`, or `llms.txt`):

   > Please refer to /path/to/pharma-skills/group-sequential-design/SKILL.md for the trial design workflow.

## Using Skills

Once installed, your agent will automatically activate relevant skills based on your task — no need to invoke them explicitly. For example, with the `admiral-adsl` skill installed:

```
You: Derive ADSL from the SDTM DM and EX domains for this study.

Agent: I'll use the admiral ADSL workflow. First, let me check the SDTM domains available...
```

Skills that bundle scripts (R or Python) will execute in your environment when the agent runs them — review a skill's contents before installing, per the [disclaimer](#disclaimer) above.

## Contributing

### New Skills 

Contributions of new skills are welcome. Each skill should:

1. Live in its own folder at the repo root
2. Include a `SKILL.md` with frontmatter (`name`, `description`) and instructions
3. Include a `README.md` describing what the skill does, requirements, and usage
4. Include an MIT `LICENSE`
5. Follow the [Agent Skill Development Lifecycle](LIFECYCLE.md)

### New Benchmark data 

You can add new benchmark data by creating new github issues following the `benchmark` templates.

### Evaluate Benchmark data 

If you're interested in contributing to the skill evaluation using your Claude Code account, following this [video](https://github.com/user-attachments/assets/05d24707-36b8-49fc-86ea-beb6365e288e) to set it up.

## License

All skills in this repository are required to be licensed under the MIT License to ensure maximum permissiveness and rapid adoption within pharmaceutical research.


## Join Us

This effort is the part of R consortium Submissions Working Group Pilot 7. It is a joint effort between the R consortium and the [BBSW AI committee](https://www.bbsw.org/ai-committee). 

Pilot 7 was initiated to help the community navigate the rapidly growing number of AI capabilities, tools, and R packages available for clinical trial workflows. One major challenge is the lack of high-quality, diverse benchmark resources, including patient-level datasets and structured test cases such as trial design scenarios. Pilot 7 addresses this gap by crowdsourcing both AI skills and benchmark resources, then using community evaluation to continuously improve them.

Pilot 7 holds weekly standups three times a month on Fridays from 8–9 AM PST. We also host monthly Submissions Working Group meetings with FDA staff, bringing together participants across different pilot subgroups.

[Pilot 7 Meeting minutes](https://github.com/RConsortium/submissions-pilot7-synthetic-data/wiki/Meeting-Minutes)

Everyone is welcome to join. To access our calendar and join the Slack workspace, please see 
[here](https://rconsortium.github.io/submissions-wg/join.html)

To learn more about the R consortium Submissions Working Group, visit [here](https://rconsortium.github.io/submissions-wg/)
