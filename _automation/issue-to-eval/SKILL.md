---
name: issue-to-eval
description: Converts one or more GitHub Issues into standardized benchmark data (evals.json) using automated scripts. Use when a user provides an issue number or URL and wants to add it to a skill's evaluation suite.
---

# Issue to Eval

Converts GitHub Issues into standardized benchmark evaluation cases (JSON) and saves them to the appropriate skill directory.

## Task Flow

1. **Import Issue Data**
   For each issue number or URL provided by the user, run the import script:
   ```bash
   python3 _automation/issue-to-eval/scripts/import_issue_eval.py --issue {ISSUE_NUMBER_OR_URL}
   ```
   
2. **Review Output**
   - The script will automatically parse headers (`## Skills`, `## Query`, etc.), deduplicate by issue ID, and append to the correct `evals/evals.json` file.
   - Report the status (Success/Skipped/Error) to the user.

## Requirements
- The issue MUST follow the standard benchmark template with headers: `## Skills`, `## Query`, `## Expected Output`, `## Attached Files / Input Context`, and `## Rubric Criteria (Assertions)`.
