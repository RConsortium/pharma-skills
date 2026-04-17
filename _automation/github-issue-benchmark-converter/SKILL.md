---
name: github-issue-benchmark-converter
description: Converts one or more GitHub Issues describing tasks, problems, or features into standardized benchmark data entries in JSON format mapping perfectly to agentskills.io schemas. Use when a user needs to curate benchmark data or parse issues into evals.
---

A skill to automatically extract benchmark data from GitHub Issues and format them as Agent Skills compliant evaluation JSON.

### Task Flow

1. **Iterate Through Inputs**:
   If the user provides multiple GitHub issues (as URLs, raw text, or JSON content), you MUST process **each issue independently**. Each issue results in exactly ONE evaluation entry.

2. **Verify the Input Format for Each Issue**:
   Examine the provided text, URL, or JSON content from the target GitHub Issue. Look for the expected markdown headers: `## Skills`, `## Query`, `## Expected Output`, `## Attached Files / Input Context`, and `## Rubric Criteria (Assertions)`.

3. **Extract Fields for Each Issue**:
   Parse the text to extract the values for each section:
   - **skill_name**: Extracted from under `## Skills`.
   - **prompt**: Extracted from under `## Query`.
   - **expected_output**: Extracted from under `## Expected Output`.
   - **files**: An array of strings extracted from under `## Attached Files / Input Context (Optional)`. (If none or left empty, make it an empty array `[]`).
   - **assertions**: An array of testable strings extracted from under `## Rubric Criteria (Assertions)`. Remove formatting bullets (like `- `) and capture the raw string assertions.

4. **Format Each as JSON**:
   Construct a JSON object matching the `agentskills.io` eval schema for each issue. DO NOT include any other keys in the schema.

   ```json
   {
     "id": "<generate a unique id or use the github issue number if presented, e.g. github-issue-45>",
     "prompt": "<extracted prompt>",
     "expected_output": "<extracted expected output>",
     "files": [
       "<extracted files array>"
     ],
     "assertions": [
       "<extracted assertions array>"
     ]
   }
   ```

5. **Batch Save the JSON to the Target Skill's Eval Folder**:
   Do NOT simply output the JSON into the chat. You must save it directly into the target skill's benchmark directory.
   - For each extracted entry, group them by their `skill_name`.
   - Target the directory: `./[skill_name]/evals/`. Create the `evals/` folder if it does not already exist.
   - **Deduplication Check**: Before appending, read the existing `evals.json` (if it exists) and check the `id` field of all entries. **Only append new entries** whose `id` does not already exist in the file.
   - If an `evals.json` file already exists, securely append the unique new eval object(s) into the existing `"evals": []` array. Ensure the JSON syntax remains valid after appending.
   - If `evals.json` does not exist, create a new file and write the full JSON payload: `{"skill_name": "<skill_name>", "evals": [<new_entries>]}`.
   - Once saved, inform the user which evaluation case(s) were added and if any were skipped as duplicates.

- If files are mentioned by name but no path is given, extract just the filenames. If a URL to a file is given, include the URL.
- Remember: exactly ONE entry is created per GitHub Issue.
