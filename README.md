# Pharma Skills

A collection of [Claude Code](https://claude.ai/code) skills for biostatistics workflows in pharmaceutical R&D.

## Skills

| Skill | Description |
|-------|-------------|
| [group_sequential_design](group_sequential_design/) | Design group sequential clinical trials for survival endpoints (OS, PFS, DFS) with interim analyses, spending functions, multiplicity, and event/enrollment prediction |

## Installation

Copy a skill folder into your project's `.claude/skills/` directory:

```
your-project/
└── .claude/
    └── skills/
        └── group_sequential_design/
            ├── SKILL.md
            ├── reference.md
            ├── examples.md
            └── ...
```

## Contributing

Contributions of new skills are welcome. Each skill should:

1. Live in its own folder at the repo root
2. Include a `SKILL.md` with frontmatter (`name`, `description`) and instructions
3. Include a `README.md` describing what the skill does, requirements, and usage
4. Include a `LICENSE`

## License

Each skill is individually licensed. See the `LICENSE` file within each skill folder.
