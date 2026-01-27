---
name: prd
description: "Generate project spec and work items from a description. Creates docs/spec.md, docs/architecture.md, and work/items.json with small, dependency-ordered work items."
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Edit
argument-hint: "[project description]"
---

# PRD Generator

Create project specification and work items for autonomous execution.

---

## Process

### Step 1: Understand the Goal

Read the project goal from arguments (`$ARGUMENTS`) or from the user.

If a goal file exists, read it:
```bash
cat work/project-goal.txt 2>/dev/null
```

### Step 2: Create docs/spec.md

Include:
- **Overview**: What the project does
- **Goals**: Measurable objectives
- **Requirements**: Functional (FR-X) and non-functional (NFR-X)
- **Constraints**: Technical limitations
- **Non-Goals**: What's explicitly out of scope
- **Acceptance Criteria**: How we know it's done

### Step 3: Create docs/architecture.md

Include:
- **System Overview**: High-level component diagram
- **Components**: Purpose, location, key files for each
- **Data Flow**: How data moves through system
- **Dependencies**: Libraries and services
- **Configuration**: Environment variables, config files

### Step 4: Create work/items.json

Break work into small items:

```json
{
  "project": "project-name",
  "branchName": "main",
  "workItems": [
    {
      "id": "WI-001",
      "title": "Initialize project",
      "description": "Set up project structure with package.json",
      "acceptanceCriteria": ["npm install works", "npm run dev starts"],
      "priority": 1,
      "status": "pending",
      "dependencies": [],
      "notes": ""
    }
  ]
}
```

### Step 5: Create docs/current-state.md

Initial state document:
- Status: 0 of N items completed
- No features implemented yet
- How to run (planned)

---

## Item Sizing Rules

**RIGHT size** (one iteration):
- "Initialize project with Vite"
- "Add user login endpoint"
- "Create navbar component"
- "Add form validation"

**TOO BIG** (split these):
- "Build authentication system" → login, register, logout, password reset
- "Create dashboard" → layout, widgets, data fetching
- "Implement API" → each endpoint separately

**Rule**: If you can't describe what to do in 2-3 sentences, split it.

---

## Item Dependencies

Use dependencies to enforce order:

```json
{
  "id": "WI-002",
  "dependencies": ["WI-001"]
}
```

Common patterns:
- Setup → everything else
- Models → endpoints that use them
- Backend → frontend that calls it
- Core features → optional features

---

## Output

```
## PRD Generated

**Project**: [name]
**Work Items**: [count]

### Files Created
- docs/spec.md
- docs/architecture.md
- docs/current-state.md
- work/items.json

### Item Summary
1. WI-001: [title]
2. WI-002: [title] (depends on WI-001)
...

**Next**: Run ./loop.sh to start implementation
```
