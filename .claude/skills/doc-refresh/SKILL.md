---
name: doc-refresh
description: "Update project documentation after implementing a feature. Maintains spec, architecture, current-state, and creates per-feature docs in docs/features/. This is about documentation, not task management."
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Edit, Glob
---

# Doc Refresh - Update Project Documentation

Maintain living documentation that describes what the system IS, how it works, and what each feature does. This skill is about **documentation quality**, not task tracking.

---

## Documentation Structure

```
docs/
├── spec.md              # Requirements, constraints, acceptance criteria
├── architecture.md      # Components, data flow, dependencies
├── current-state.md     # What's built, how to run, known limitations
└── features/            # One doc per feature/module
    ├── chunk-system.md
    ├── noise-generation.md
    ├── player-controls.md
    └── ...
```

---

## Step 1: Write Feature Documentation (ALWAYS)

Create or update a doc in `docs/features/` for the feature just implemented.

```bash
mkdir -p docs/features
```

Each feature doc should include:

```markdown
# Feature Name

## Overview
What this feature does and why it exists.

## How It Works
Technical explanation of the implementation approach.
Key algorithms, data structures, patterns used.

## API / Interface
Public functions, classes, or endpoints exposed.
Parameters, return values, usage examples.

## Data Flow
How data moves through this feature.
Inputs → Processing → Outputs.

## Files
- `src/path/file.js` - Description
- `src/path/other.js` - Description

## Dependencies
What this feature depends on (other features, libraries).

## Configuration
Any settings, constants, or tunables.
```

Name the file after the feature: `docs/features/noise-generation.md`, `docs/features/chunk-meshing.md`, etc.

---

## Step 2: Update docs/current-state.md (ALWAYS)

Read the current file, then update:
- **What's Built**: List of implemented features with brief descriptions
- **How to Run**: Setup and run commands (update if changed)
- **Known Limitations**: What doesn't work yet or has caveats
- **Recent Changes**: What was just added/modified

Do NOT include task IDs, task counts, or task status here. This doc describes the **system**, not the project management state.

---

## Step 3: Update docs/architecture.md (IF structure changed)

Update when:
- New component or module added
- Data flow between components changed
- New external dependency introduced
- New directory or file structure created

Keep this doc focused on **how the system is structured** — components, their responsibilities, how they connect, and where things live in the codebase.

---

## Step 4: Update docs/spec.md (IF requirements clarified)

Update when:
- A requirement was clarified during implementation
- An open question was answered
- A new constraint was discovered
- A non-goal was identified

---

## Step 5: Append to work/progress.txt (ALWAYS)

This is a chronological log of what happened, distinct from the living docs above.

```bash
cat >> work/progress.txt << 'PROGRESS_EOF'

## YYYY-MM-DD - Feature: Name
- What was implemented
- Key decisions made
- Patterns discovered
PROGRESS_EOF
```

---

## Why Per-Feature Docs Matter

As the project grows, the docs/ folder becomes a knowledge base. The memory tool (`memory.py index` + `find`) can then search across all feature docs to find relevant context for new tasks. Without per-feature docs, the agent loses context on how existing features work as the codebase grows beyond what fits in a single context window.

---

## Output Format

```
## Documentation Updated

### Feature Doc
- Created/Updated: docs/features/[name].md

### current-state.md
- Updated: [what changed]

### architecture.md
- [Updated section] or [No changes needed]

### spec.md
- [Updated section] or [No changes needed]

### progress.txt
- Appended session log
```
