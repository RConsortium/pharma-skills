import json
import subprocess
import argparse
import sys
import os
import re

def clean_value(val):
    """Strips leading bullets, hyphens, and whitespace."""
    if not val:
        return ""
    # Remove leading markdown bullets/hyphens and common list markers
    cleaned = re.sub(r'^[\s\-\*•]+', '', val.strip())
    return cleaned.strip()

def parse_issue_markdown(body):
    """
    Extracts fields from a GitHub issue body based on markdown headers.
    Headers: ## Skills, ## Query, ## Expected Output, ## Attached Files / Input Context (Optional), ## Rubric Criteria (Assertions)
    """
    sections = {
        "skill": r"## Skills\s+(.*?)(?=\n##|$)",
        "prompt": r"## Query\s+(.*?)(?=\n##|$)",
        "expected_output": r"## Expected Output\s+(.*?)(?=\n##|$)",
        "files": r"## Attached Files / Input Context \(Optional\)\s+(.*?)(?=\n##|$)",
        "assertions": r"## Rubric Criteria \(Assertions\)\s+(.*?)(?=\n##|$)"
    }
    
    data = {}
    for key, pattern in sections.items():
        match = re.search(pattern, body, re.DOTALL | re.IGNORECASE)
        content = match.group(1).strip() if match else ""
        
        if key == "skill":
            data["skill_name"] = clean_value(content).lower().replace(" ", "-")
        elif key == "files":
            data["files"] = [clean_value(f) for f in content.split("\n") if clean_value(f)]
        elif key == "assertions":
            data["assertions"] = [clean_value(a) for a in content.split("\n") if clean_value(a)]
        else:
            data[key] = clean_value(content)
            
    return data

def save_to_evals(eval_entry, skill_name):
    if not skill_name or skill_name == "unknown-skill":
        return "Error: Could not determine target skill name from issue."

    target_dir = os.path.join(skill_name, "evals")
    os.makedirs(target_dir, exist_ok=True)
    eval_file = os.path.join(target_dir, "evals.json")
    
    if os.path.exists(eval_file):
        with open(eval_file, "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                data = {"skill_name": skill_name, "evals": []}
    else:
        data = {"skill_name": skill_name, "evals": []}
        
    # Deduplicate by ID
    existing_ids = {e.get("id") for e in data["evals"]}
    if eval_entry["id"] in existing_ids:
        return f"Skipped: {eval_entry['id']} already exists in {skill_name}/evals/evals.json"
        
    data["evals"].append(eval_entry)
    
    with open(eval_file, "w") as f:
        json.dump(data, f, indent=2)
    
    return f"Success: Added {eval_entry['id']} to {skill_name}/evals/evals.json"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--issue", required=True, help="GitHub Issue number or URL")
    args = parser.parse_args()
    
    # Extract number from URL or #N or N
    issue_match = re.search(r'(\d+)$', args.issue)
    if not issue_match:
        print(f"Error: Could not parse issue number from '{args.issue}'", file=sys.stderr)
        sys.exit(1)
    
    issue_id = issue_match.group(1)
    
    try:
        result = subprocess.run(
            ["gh", "issue", "view", issue_id, "--json", "number,body,title"],
            capture_output=True, text=True, check=True
        )
        issue_data = json.loads(result.stdout)
        
        parsed = parse_issue_markdown(issue_data["body"])
        
        eval_entry = {
            "id": f"github-issue-{issue_data['number']}",
            "prompt": parsed.get("prompt", ""),
            "expected_output": parsed.get("expected_output", ""),
            "files": parsed.get("files", []),
            "assertions": parsed.get("assertions", [])
        }
        
        status = save_to_evals(eval_entry, parsed.get("skill_name", ""))
        print(status)
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
