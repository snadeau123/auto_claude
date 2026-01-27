---
name: loop
description: "Execute one iteration of the autonomous development loop. Gets task, reads context with memory tool, implements, tests via /functional-test, security checks via /security-scan, updates docs via /doc-refresh, commits."
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill
---

# Auto Claude Loop - One Iteration

You are an autonomous coding agent. Execute these steps IN ORDER. Do NOT skip any step. Each step must produce visible output before moving to the next.

---

## STEP 1: Get Next Task

```bash
python3 .claude/tools/tasks.py next
```

If output includes `<promise>COMPLETE</promise>`, output that signal and STOP immediately.

Parse the task ID (e.g., `WI-004`) and title from the output.

---

## STEP 2: Mark Task In Progress

```bash
python3 .claude/tools/tasks.py update WI-XXX --status in_progress
```

Replace `WI-XXX` with the actual task ID from step 1.

---

## STEP 3: Load Context

**3a. Read core documents** using your native Read tool:
- `docs/spec.md` - Requirements
- `docs/architecture.md` - System design
- `docs/current-state.md` - Current status

**3b. Index and search project documentation** with the memory tool:
```bash
python3 .claude/tools/memory.py index
```

Then search for context relevant to the current task:
```bash
python3 .claude/tools/memory.py find "<keywords from task title/description>"
```

If search returns relevant sections, use `peek` or `chunk` to read them:
```bash
python3 .claude/tools/memory.py peek <file> --lines 100
python3 .claude/tools/memory.py chunk <file> --by sections
```

**3c. Read existing source files** related to the task using your Read tool.

---

## STEP 4: Implement

Write the code for the task.

### For Node.js Projects
```bash
npm install
npm run dev  # or npm start
```

### For Python Projects
```bash
# Use miniconda if available
if [ -d "./miniconda3" ]; then
  source ./miniconda3/bin/activate
  conda activate ./conda_env 2>/dev/null || conda create -p ./conda_env python=3.11 -y && conda activate ./conda_env
fi

# Or use venv
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### Guidelines
- Keep changes minimal and focused on the task
- Follow existing code patterns found in Step 3
- Don't add features beyond what the task specifies

---

## STEP 5: Test

Invoke the `/functional-test` skill to verify the implementation:

```
Use Skill tool: skill="functional-test"
```

This will use Chrome MCP browser automation to take screenshots, interact with the UI, and check console errors.

For non-UI tasks, run the appropriate test suite:
```bash
# Python
pytest tests/ -v

# Node.js
npm test

# API
curl http://localhost:3000/api/endpoint
```

If tests fail, fix the issues and re-test before proceeding.

---

## STEP 6: Security Scan

Invoke the `/security-scan` skill to check for vulnerabilities:

```
Use Skill tool: skill="security-scan"
```

This checks for hardcoded secrets, input validation issues, auth bypass, and OWASP Top 10 patterns. If critical issues are found, fix them before proceeding.

---

## STEP 7: Update Documentation

Invoke the `/doc-refresh` skill to update all project docs:

```
Use Skill tool: skill="doc-refresh"
```

This updates `docs/current-state.md`, `docs/architecture.md` (if needed), `docs/spec.md` (if needed), and appends to `work/progress.txt`.

---

## STEP 8: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(WI-XXX): Brief description of what was implemented

- Detail 1
- Detail 2

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Replace `WI-XXX` with the actual task ID. The commit message MUST include the `Co-Authored-By` line.

---

## STEP 9: Mark Complete & Report

```bash
python3 .claude/tools/tasks.py update WI-XXX --status completed
python3 .claude/tools/tasks.py stats
```

Output a summary in this exact format:

```
## Iteration Complete

**Task**: WI-XXX - Title
**Status**: completed
**Changes**: Brief summary of what was done
**Tests**: passed/failed (include /functional-test result)
**Security**: passed/failed (include /security-scan result)
**Docs**: updated (include /doc-refresh result)
**Context**: XX% used
**Next**: WI-YYY or COMPLETE

[If all tasks done: <promise>COMPLETE</promise>]
```

---

## STEP 10: Context-Aware Continuation

After completing a task, check the context usage from the hook telemetry (shown in system reminders after each tool call, e.g. `[Context telemetry:XX% | estimation from transcript:XX%]`). Use whichever value is higher.

**If context < 60%**: Go back to STEP 1 and start the next task. You have budget remaining — use it.

**If context >= 60%**: Stop. You are done for this session.

**If all tasks are done**: Output `<promise>COMPLETE</promise>` and stop.

---

## Context Exhaustion — Handoff Protocol

If at any point during implementation you notice context usage is approaching **80%+** and you have NOT finished the current task:

1. **Do NOT rush to a broken commit.** Only commit if the code is in a working state.
2. **Save your progress** by updating `work/progress.txt` with:
   - What you accomplished so far on this task
   - What remains to be done
   - Your planned approach for the remaining work
   - Any decisions made or patterns discovered
3. **Update task status** with notes:
   ```bash
   python3 .claude/tools/tasks.py update WI-XXX --status in_progress --notes "Partial: <what's done>. Remaining: <what's left>. Approach: <how to finish>."
   ```
4. Stop. The next session will pick up where you left off via `tasks.py next` (which returns in_progress tasks first) and can read your notes from progress.txt.

---

## Error Handling

### If stuck after 3 attempts:
```bash
python3 .claude/tools/tasks.py update WI-XXX --status blocked --notes "Reason for block"
```
Then move to next task.

### If tests fail persistently:
Document the failure in progress.txt and continue with next task.

### If a skill fails to invoke:
Fall back to performing that step manually (inline the checks).

---

## Step Checklist

Before finishing, verify ALL steps were completed for each task:

- [ ] Task fetched with `tasks.py next`
- [ ] Task marked `in_progress`
- [ ] Core docs read (spec, architecture, current-state)
- [ ] Memory tool used (`index` + `find`)
- [ ] Code implemented
- [ ] `/functional-test` invoked
- [ ] `/security-scan` invoked
- [ ] `/doc-refresh` invoked
- [ ] Git commit created with Co-Authored-By
- [ ] Task marked `completed`
- [ ] Summary report output
- [ ] Context checked — continue or stop
