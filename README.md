# Pharma Skills

A collection of agent skills for pharmaceutical R&D.

## Skills

| Skill | Description |
|-------|-------------|
| [group-sequential-design](group-sequential-design/) | Design group sequential clinical trials for survival endpoints (OS, PFS, DFS) with interim analyses, spending functions, multiplicity, and event/enrollment prediction |
| [clinical-trial-simulation](clinical-trial-simulation/) | Design and simulate clinical trials using the TrialSimulator R package and produce a QC-ready build-order-spine report. Design-agnostic: composes from independent building blocks (endpoints, arms, milestones, regimens) rather than following a fixed catalog of design templates. |
| [admiral/admiral-adsl](admiral/admiral-adsl/) | Derive ADaM Subject-Level Analysis Datasets (ADSL) from SDTM domains using the {admiral} R package. Encodes the workflow, function selection logic, and CDISC conventions for QC-ready, submission-traceable R code. |
| [admiral/admiral-bds](admiral/admiral-bds/) | Derive ADaM BDS findings datasets (ADVS, ADLB) from SDTM VS/LB domains. Covers parameter assignment, baseline flagging, change from baseline, visit windowing, and ADLB normal range derivations. |
| [clinical-trial-ipd-sim](clinical-trial-ipd-sim/) | Generate synthetic IPD, source CRFs, SDTM, ADaM, and exports for registered clinical trials using an R/pharmaverse g-formula causal-DAG workflow calibrated to posted protocol and results. |
| [statistical-reviewer](statistical-reviewer/) | Simulate an independent statistical reviewer auditing a clinical trial submission package (SDTM, ADaM, TLF, SAP, CSR) — reproducing endpoints, tracing results across data layers, flagging population inconsistencies, and assessing data realism. |

## Usage

**Option 1: Conversational / CLI**
Ask your agent to directly enable a skill from this repo:
> enable "group-sequential-design" skill from https://github.com/RConsortium/pharma_skills

**Option 2: Local IDE (Cursor, Windsurf, Copilot, etc.)**
1. Clone this repository locally or as a git submodule.
2. Symlink the skill you want into your project, or manually reference it in your configuration files (like `.cursorrules` or `llms.txt`):
   `Please refer to /path/to/pharma_skills/group-sequential-design/SKILL.md for the trial design workflow.`

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
