# Evidence channel — Paperclip

All literature/evidence lookups in this skill (causal-parent evidence, natural-history rates,
parameter priors, CTCAE/RECIST references) go through **Paperclip** — the `literature-search-paperclip`
CLI — so every claim resolves to a source and its exact text. Paperclip is the **recommended** channel;
if it is unavailable, any citation-capable lookup may substitute, but the **citation format below stays
mandatory and fail-closed** (a row with no source fails, never a row because paperclip is absent).

## Install (once per device)

```bash
scripts/setup_paperclip.sh        # detects an existing install, else installs the CLI
```

That script is just: `command -v paperclip || curl -fsSL https://paperclip.gxl.ai/install.sh | bash`.
It is **not** run automatically — invoke it as an opt-in step, and it will prompt before installing.
Then authenticate once: `paperclip login` (or `export PAPERCLIP_API_KEY=…`), verify with `paperclip config`.

## Sources

| `--source` | Contents | Good for |
|---|---|---|
| `pmc` | ~7.5M open-access full-text papers | peer-reviewed evidence, mechanisms |
| `fda` | ~225K regulatory documents / labels | approved effect sizes, AE rates |
| `trials/us` | ~580K ClinicalTrials.gov records | a specific trial's registration/results |
| `abstracts_only` | ~50M OpenAlex abstracts | broad coverage |
| `preprints` | bioRxiv / medRxiv / arXiv | latest work |

## Pattern: scope → search → filter → map

```bash
paperclip search --all --source pmc --tag q "<topic / claim>"
paperclip filter --from <s_id> --require 2 "<what makes a paper relevant>"
paperclip map --from <s_id> \
  --output_schema '{"finding":"string","value":"string|null","population":"string","source_id":"string","url":"string","quote":"verbatim text, <=2-3 sentences"}' \
  "<what to read each paper for>"
```

`map` returns one structured record per paper. Every record carries the **citation core**:
`source_id` (e.g. `pmc_8567001`), a resolvable `url`, and the **verbatim `quote`** the value came from.
Use `lookup pmid <PMID>` / `grep -i "<pat>" /papers/<id>/content.lines` to resolve ids and pull exact quotes.

## Citation core → this skill's Source / Evidence columns

Every evidence-backed row of `dag_spec.md` / `DAG.md`, the parameter table, and the SCM dossier maps the
paperclip citation core into the skill's two mandatory columns:

| Skill column | From paperclip | Rule |
|---|---|---|
| **Source** | origin tag + `source_id`/`url` | one of `ctgov: <field path>` · `paperclip: <source_id> <url>` · `model: <default>` (model = flagged, no external source) |
| **Evidence** | `quote` | the **verbatim** text, copied not paraphrased; required on every row |

Example row: `time_to_resistance (arm) | paperclip: pmc_8567001 https://… | "median PFS 25.5 vs 16.7 months (HR 0.62; 95% CI 0.49–0.79)"`.

Fail closed on a **missing citation**, never on paperclip's absence — the citation rule holds whichever
lookup provides the source (the paperclip command surface is shown above).
