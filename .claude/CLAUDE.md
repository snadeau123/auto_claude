# Instructions

You have access to custom tools and skills described below. Use them when working on this project.

## Tools

**Important**: Use `tasks.py` for all task management in this project — do NOT use Claude's built-in TaskCreate/TaskUpdate/TaskList tools.

### Task Management
| Command | Purpose |
|---------|---------|
| `python3 .claude/tools/tasks.py next` | Get next task |
| `python3 .claude/tools/tasks.py list` | List all tasks |
| `python3 .claude/tools/tasks.py create '<title>' '<desc>'` | Create a single task |
| `python3 .claude/tools/tasks.py init <project> -f <file>` | Initialize tasks from JSON array |
| `python3 .claude/tools/tasks.py update <id> --status <s>` | Update task status |
| `python3 .claude/tools/tasks.py stats` | Show completion statistics |
| `python3 .claude/tools/tasks.py reconcile` | Sync task status with git commits |

### Memory Tool (for large documentation)
Use Claude's native Read tool for basic files (spec.md, architecture.md, etc.).
The memory tool is for navigating **large documentation sets** that won't fit in context — especially the growing `docs/features/` folder.

| Command | Purpose |
|---------|---------|
| `python3 .claude/tools/memory.py index [--path DIR]` | Build TF-IDF index over docs |
| `python3 .claude/tools/memory.py find "<query>" [--top N]` | Semantic search across all docs |
| `python3 .claude/tools/memory.py peek <file> [--lines N]` | Preview first N lines of a file |
| `python3 .claude/tools/memory.py chunk <file> [--by sections\|lines]` | Split file for batched queries |
| `python3 .claude/tools/memory.py topics` | List all indexed sections |
| `python3 .claude/tools/memory.py stats` | Index statistics |
| `python3 .claude/tools/memory.py batch "<query>" --files f1,f2` | Search specific files |

Based on [Recursive Language Models](https://arxiv.org/abs/2512.24601) paper concepts.

## Skills

| Skill | Purpose |
|-------|---------|
| `/loop` | Execute one autonomous iteration (used by loop.sh) |
| `/prd` | Generate spec, architecture, and work items for a new project |
| `/functional-test` | Test the app using Playwright (preferred) or Chrome MCP |
| `/playwright-test` | Direct Playwright browser automation |
| `/security-scan` | Scan for secrets, injection, OWASP issues before committing |
| `/doc-refresh` | Update project docs and create per-feature documentation |

## Documentation Structure

```
docs/
├── spec.md              # Requirements, constraints, acceptance criteria
├── architecture.md      # Components, data flow, dependencies
├── current-state.md     # What's built, how to run, known limitations
└── features/            # Per-feature documentation (indexed by memory tool)
    ├── chunk-system.md
    ├── noise-generation.md
    └── ...
```

## Documentation Principles

- Read small docs (spec.md, architecture.md, current-state.md) directly with your Read tool
- Use the memory tool (`index` + `find`) when documentation grows too large for context
- After implementing a feature, always create or update a doc in `docs/features/`
- Documentation describes the **system**, not project management state

## Research Before Implementing

Before writing code, search the docs for **related** systems — not just the task topic itself.
Ask: what existing systems will this touch or integrate with? Search for those to understand
the established patterns before implementing your part.

For example, if your task writes to a shared data file, search for how other features read/write
that file. If your task adds a UI component, search for how existing components are structured.
The goal is to follow conventions already in place, not invent new ones.
