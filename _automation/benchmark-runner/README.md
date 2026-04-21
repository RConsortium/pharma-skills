# Skill Benchmark Runner

The **Skill Benchmark Runner** is an automated framework designed to quantify the value of an AI agent skill. It performs a "fair fight" comparison between two agents—one equipped with the specialized `SKILL.md` and one using only its base knowledge—to measure improvements in accuracy, efficiency, and consistency.

## How It Works

1.  **Discovery**: Scans the `evals/` directory for all `.json` evaluation cases.
2.  **Deduplication**: Checks the linked GitHub issues (e.g., `#21`) to see if a benchmark has already been posted for the **current skill version (Git SHA)** and the **current model** (e.g., GPT-4o, Gemini 2.0 Flash, Claude 3.7 Sonnet).
3.  **Parallel Execution**: Launches two independent sub-agents simultaneously:
    *   **Agent A (With Skill)**: Pre-loaded with the `SKILL.md` instructions and all supporting resources.
    *   **Agent B (Without Skill)**: Given only the raw prompt and files, with explicit instructions *not* to use any skill data.
4.  **Objective Scoring**: Evaluates the artifacts produced by both agents (code, data, reports) against a set of predefined **Assertions**.
5.  **Performance Tracking**: Records technical metrics including **Execution Time**, **Token Usage**, and **Tool Success Rates**.
6.  **Reporting**: Generates a detailed Markdown report and posts it as a comment on the originating GitHub issue.

## Understanding Evaluation Files (Example: Issue #21)

Each evaluation JSON file controls a different part of the benchmark lifecycle. Using **Issue #21** as an example:

| Field | Purpose | Lifecycle Role |
|---|---|---|
| **`id`** | `"github-issue-21"` | **Deduplication & Posting**: Used to check if this benchmark already exists on GitHub and where to post the results. |
| **`prompt`** | `"I'm designing a Phase 3 trial..."` | **Agent Input**: This is the raw request given to both Agents. It defines the constraints (N < 450) and statistical parameters. |
| **`files`** | `[]` (None in this case) | **Context**: Any URLs or local paths listed here are downloaded and attached to both agents so they have the same data context. |
| **`expected_output`** | `"All outputs in output/...R, .json..."` | **Documentation**: Describes the target state. It is used by humans to understand what files the agents are expected to create. |
| **`assertions`** | `["gsd_design.R exists...", "total_N < 450..."]` | **Grading**: The automated rubric. After agents finish, their `output_A/` and `output_B/` are checked against these rules to calculate the score. |

## Benchmark Report Features

Each automated report provides a deep-dive comparison:

| Section | Description |
|---|---|
| **Run Metadata** | Captures the Model, Skill SHA, and a link to **Detailed Outputs** (Zip or Gist). |
| **Scorecard** | High-level comparison of the total Score (%), Assertions met, and performance metrics (Time/Tokens). |
| **Assertion Breakdown** | A line-by-line check of where each agent succeeded or failed. |
| **Key Observations** | Human-readable analysis of the qualitative differences in code quality or reasoning. |
| **Debugging Info** | Collapsible technical logs showing tool call success rates and any system errors/retries. |

## Adding New Benchmarks

To add a new test case to a skill's evaluation suite:
1.  Open a new GitHub Issue with the `benchmark` label.
2.  Follow the template headers: `## Skills`, `## Query`, `## Expected Output`, and `## Rubric Criteria (Assertions)`.
3.  Run the **Issue to Eval** skill (`python3 _automation/issue-to-eval/scripts/sync_benchmarks.py`) to automatically import the issue into the `_automation/evals/` directory.

## Usage

### As a Scheduled Workflow
This tool is optimized for CI/CD or scheduled task runners. Provide the `SKILL.md` as the system instruction and trigger it periodically to ensure skill quality doesn't regress as the codebase evolves.

### Manual Trigger
Ask your agent:
> "Run benchmarks for the group-sequential-design skill."
> "Compare the latest skill version against the base model for Issue #21."

## Requirements
- **GitHub CLI (`gh`)**: Must be authenticated with write access to post comments and read issues.
- **Agent Tool**: Required for launching parallel sub-agents (e.g., using the `generalist` tool).

## License
MIT

MIT
