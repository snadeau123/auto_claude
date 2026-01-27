#!/bin/bash
# Auto Claude - Long-running autonomous coding session loop
# Usage: .claude/loop.sh [--max-iterations N] [--init "project description"] [--model MODEL] [--no-sandbox]
#
# Spawns fresh Claude instances per iteration, checking for completion signal.

# Note: set -e is intentionally NOT used — the loop must continue even if iterations fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ITEMS_FILE="$PROJECT_ROOT/work/items.json"
PROGRESS_FILE="$PROJECT_ROOT/work/progress.txt"
GOAL_FILE="$PROJECT_ROOT/work/project-goal.txt"
LOGS_DIR="$PROJECT_ROOT/work/logs"

# Default settings
MAX_ITERATIONS=50
USE_SANDBOX=true
INIT_PROMPT=""
MODEL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-iterations=*)
      MAX_ITERATIONS="${1#*=}"
      shift
      ;;
    --sandbox)
      USE_SANDBOX=true
      shift
      ;;
    --no-sandbox)
      USE_SANDBOX=false
      shift
      ;;
    --init)
      INIT_PROMPT="$2"
      shift 2
      ;;
    --init=*)
      INIT_PROMPT="${1#*=}"
      shift
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#*=}"
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Create directories
mkdir -p "$LOGS_DIR"
mkdir -p "$PROJECT_ROOT/work"

# Initialize progress file if needed
if [ ! -f "$PROGRESS_FILE" ]; then
  cat > "$PROGRESS_FILE" << 'EOF'
# Progress Log

## Codebase Patterns
(Add patterns discovered during implementation)

---

## Session Log

EOF
fi

# Ensure Playwright is installed (runs outside sandbox so binaries are cached)
PLAYWRIGHT_SKILL_DIR="$PROJECT_ROOT/.claude/skills/playwright-test"
if [ -f "$PLAYWRIGHT_SKILL_DIR/package.json" ]; then
  if [ ! -d "$PLAYWRIGHT_SKILL_DIR/node_modules/playwright" ]; then
    echo "Installing Playwright..."
    (cd "$PLAYWRIGHT_SKILL_DIR" && npm install --silent 2>/dev/null && npx playwright install chromium 2>/dev/null) || echo "Playwright install failed — will use fallback testing"
  fi
fi

# Sandbox config allowing Claude's own directories
# Note: srt doesn't support individual file paths in allowWrite, only directories
# so we allow $HOME for .claude.json writes (Claude's own config/auth state)
SANDBOX_CONFIG_FILE=""
if [ "$USE_SANDBOX" = true ] && command -v srt &> /dev/null; then
  SANDBOX_CONFIG_FILE=$(mktemp /tmp/auto-claude-sandbox-XXXXXX.json)
  cat > "$SANDBOX_CONFIG_FILE" <<SRTEOF
{
  "network": {
    "allowedDomains": [
      "github.com", "*.github.com", "*.githubusercontent.com",
      "api.anthropic.com", "*.anthropic.com",
      "pypi.org", "*.pypi.org", "files.pythonhosted.org",
      "registry.npmjs.org", "*.npmjs.org"
    ],
    "deniedDomains": [],
    "allowAllUnixSockets": true
  },
  "filesystem": {
    "denyRead": ["$HOME/.ssh", "$HOME/.gnupg", "$HOME/.aws"],
    "allowWrite": [".", "$HOME", "/tmp"],
    "denyWrite": [".env", "*.key", "*.pem"],
    "allowRead": ["$HOME/.cache/ms-playwright"]
  }
}
SRTEOF
  trap "rm -f $SANDBOX_CONFIG_FILE" EXIT
fi

# Build model flag if specified
MODEL_FLAG=""
if [ -n "$MODEL" ]; then
  MODEL_FLAG="--model $MODEL"
fi

# Check if we need to initialize the project
ITEM_COUNT=$(jq '.workItems | length' "$ITEMS_FILE" 2>/dev/null || echo "0")

if [ "$ITEM_COUNT" = "0" ]; then
  if [ -n "$INIT_PROMPT" ]; then
    echo "=============================================="
    echo "  Initializing Project"
    echo "=============================================="
    echo "Goal: $INIT_PROMPT"
    echo ""

    # Save project goal
    echo "$INIT_PROMPT" > "$GOAL_FILE"

    # Run PRD generation
    PRD_PROMPT="You are initializing a new project. The user wants to build:

$INIT_PROMPT

Your task:
1. Create docs/spec.md with requirements, constraints, acceptance criteria
2. Create docs/architecture.md with system design
3. Create work/items.json with small work items (each completable in one session)

Guidelines for work items:
- RIGHT size: 'Add database model', 'Create UI component', 'Add API endpoint'
- TOO BIG: 'Build entire dashboard', 'Implement auth system'
- If you can't describe it in 2-3 sentences, split it

Do NOT ask questions. Make reasonable assumptions. Output a summary when done."

    LOG_FILE="$LOGS_DIR/init-$(date '+%Y%m%d-%H%M%S').log"
    echo "Log: $LOG_FILE"

    if [ "$USE_SANDBOX" = true ] && [ -n "$SANDBOX_CONFIG_FILE" ]; then
      srt -s "$SANDBOX_CONFIG_FILE" -c "claude $MODEL_FLAG --chrome --dangerously-skip-permissions -p \"$PRD_PROMPT\"" 2>&1 | tee "$LOG_FILE"
    else
      claude $MODEL_FLAG --chrome --dangerously-skip-permissions -p "$PRD_PROMPT" 2>&1 | tee "$LOG_FILE"
    fi

    echo ""
    echo "Initialization complete. Starting loop..."
    sleep 2
  else
    echo "Error: No work items. Use --init 'description' to start a project."
    exit 1
  fi
fi

# Load project goal for workflow prompt
PROJECT_GOAL=""
if [ -f "$GOAL_FILE" ]; then
  PROJECT_GOAL=$(cat "$GOAL_FILE")
fi

echo "=============================================="
echo "  Auto Claude Loop"
echo "=============================================="
echo "Max iterations: $MAX_ITERATIONS"
echo "Sandbox: $USE_SANDBOX"
[ -n "$MODEL" ] && echo "Model: $MODEL"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Iteration $i of $MAX_ITERATIONS - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "==============================================================="

  LOG_FILE="$LOGS_DIR/iteration-$i-$(date '+%Y%m%d-%H%M%S').log"

  # Comprehensive workflow prompt
  PROMPT="You are an autonomous coding agent. Follow EVERY step below. Do NOT skip any step.

PROJECT GOAL:
$PROJECT_GOAL

WORKFLOW - Execute each step and produce visible output before moving to the next:

STEP 1: GET NEXT TASK
Run: python3 .claude/tools/tasks.py next
If output contains '<promise>COMPLETE</promise>', output that and stop immediately.

STEP 2: MARK IN PROGRESS
Run: python3 .claude/tools/tasks.py update WI-XXX --status in_progress

STEP 3: LOAD CONTEXT (read ALL three files, do NOT skip any)
3a. Read docs/spec.md - understand requirements and constraints
3b. Read docs/architecture.md - understand system structure and components
3c. Read docs/current-state.md - understand what is built and how to run it
3d. REQUIRED - Run the memory tool to search for task-relevant context:
    python3 .claude/tools/memory.py index
    python3 .claude/tools/memory.py find 'keywords from task title'
3e. REQUIRED - Search for RELATED features, not just the task itself.
    Before implementing, think: what existing systems will this task touch or integrate with?
    Search for those systems in the docs to understand established patterns and conventions.
    Example: if your task is 'add export button', search for how other buttons work, how
    file I/O is done, how the UI layer is structured — not just 'export'.
    Run additional memory.py find queries for each related system you identify.
3f. Read existing source files related to the task.

STEP 4: IMPLEMENT
Follow the patterns and conventions discovered in step 3e. Keep changes minimal and focused.

STEP 5: TEST - INVOKE THE /functional-test SKILL
You MUST use the Skill tool to invoke: skill='functional-test'
This runs Chrome MCP browser automation to verify the UI works.
For non-UI tasks, also run: npm test / pytest as appropriate.

STEP 6: SECURITY SCAN - INVOKE THE /security-scan SKILL
You MUST use the Skill tool to invoke: skill='security-scan'
This checks for hardcoded secrets, injection patterns, and OWASP issues.

STEP 7: UPDATE DOCS - INVOKE THE /doc-refresh SKILL
You MUST use the Skill tool to invoke: skill='doc-refresh'
This updates current-state.md, architecture.md, spec.md, and progress.txt.

STEP 8: COMMIT
Run: git add -A
Run: git commit with message format 'feat(WI-XXX): description' and MUST include 'Co-Authored-By: Claude <noreply@anthropic.com>'

STEP 9: MARK COMPLETE AND REPORT
Run: python3 .claude/tools/tasks.py update WI-XXX --status completed
Run: python3 .claude/tools/tasks.py stats
Output a summary with: Task ID, what changed, test result, security result, docs updated, context % used, next task or <promise>COMPLETE</promise>

STEP 10: CONTEXT-AWARE CONTINUATION
Check the context usage from the hook telemetry shown in system reminders (e.g. [Context telemetry:XX% | estimation from transcript:XX%]). Use whichever value is higher.
- If context < 60%: Go back to STEP 1 and start the next task immediately. You have budget remaining.
- If context >= 60%: Stop. You are done for this session.
- If all tasks done: Output <promise>COMPLETE</promise> and stop.

CONTEXT EXHAUSTION HANDOFF:
If context reaches 80%+ and you have NOT finished the current task:
1. Do NOT rush to a broken commit. Only commit working code.
2. Update work/progress.txt with: what you did, what remains, your planned approach.
3. Run: python3 .claude/tools/tasks.py update WI-XXX --status in_progress --notes 'Partial: what was done. Remaining: what is left. Approach: how to finish.'
4. Stop. The next session picks up via tasks.py next.

CHECKLIST - For each task, verify ALL of these:
[ ] tasks.py next called
[ ] Task marked in_progress
[ ] Read spec.md, architecture.md, current-state.md (all three)
[ ] memory.py index + find called
[ ] Code implemented
[ ] /functional-test skill invoked
[ ] /security-scan skill invoked
[ ] /doc-refresh skill invoked
[ ] Git commit with Co-Authored-By
[ ] Task marked completed
[ ] Context checked — continue or stop

START NOW - Run step 1."

  echo "Log: $LOG_FILE"

  if [ "$USE_SANDBOX" = true ] && [ -n "$SANDBOX_CONFIG_FILE" ]; then
    OUTPUT=$(srt -s "$SANDBOX_CONFIG_FILE" -c "claude $MODEL_FLAG --chrome --dangerously-skip-permissions -p \"$PROMPT\"" 2>&1 | tee "$LOG_FILE") || true
  else
    OUTPUT=$(claude $MODEL_FLAG --chrome --dangerously-skip-permissions -p "$PROMPT" 2>&1 | tee "$LOG_FILE") || true
  fi

  # Reconcile: auto-complete tasks with git commits, reset stale in_progress
  python3 .claude/tools/tasks.py reconcile 2>/dev/null || true

  # Check for completion
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "=============================================="
    echo "  ALL TASKS COMPLETE!"
    echo "=============================================="
    exit 0
  fi

  # Check remaining items
  PENDING=$(jq '[.workItems[] | select(.status == "pending" or .status == "in_progress")] | length' "$ITEMS_FILE" 2>/dev/null || echo "0")
  if [ "$PENDING" = "0" ]; then
    echo "No pending tasks. Done."
    exit 0
  fi

  echo "Iteration $i done. $PENDING tasks remaining."
  sleep 2
done

echo ""
echo "Max iterations ($MAX_ITERATIONS) reached."
echo "Run again to continue."
exit 1
