#!/bin/bash
# Auto Claude - Long-running autonomous coding session loop
# Usage: .claude/loop.sh [--max-iterations N] [--init "project description"] [--request "change or bug"] [--model MODEL] [--no-sandbox]
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
REQUEST=""
MODEL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat <<'HELP'
Auto Claude - Autonomous coding session loop

Usage: .claude/loop.sh [OPTIONS]

Options:
  --init "description"       Initialize a new project (generates spec, architecture, work items)
  --request "text"           Feature request, bug report, or guidance for the first iteration
  --max-iterations N         Max loop iterations (default: 50)
  --model MODEL              Claude model to use
  --no-sandbox               Disable srt sandbox
  --sandbox                  Enable srt sandbox (default)
  -h, --help                 Show this help

Examples:
  .claude/loop.sh --init "A 2D platformer game with level editor"
  .claude/loop.sh --max-iterations 5
  .claude/loop.sh --request "The player clips through walls when moving fast"
  .claude/loop.sh --request "Add a settings menu with volume and keybind options"
HELP
      exit 0
      ;;
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
    --request)
      REQUEST="$2"
      shift 2
      ;;
    --request=*)
      REQUEST="${1#*=}"
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

# Use dedicated auto_claude config dir — keeps auth separate from ~/.claude.json
AUTO_CLAUDE_HOME="$HOME/.auto_claude"
mkdir -p "$AUTO_CLAUDE_HOME"
if [ ! -f "$AUTO_CLAUDE_HOME/.claude.json" ]; then
  echo "No auth found. Running first-time setup..."
  CLAUDE_CONFIG_DIR="$AUTO_CLAUDE_HOME" claude setup-token
fi
export CLAUDE_CONFIG_DIR="$AUTO_CLAUDE_HOME"

# Sandbox config
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
    "denyRead": ["$HOME/.ssh", "$HOME/.gnupg", "$HOME/.git-credentials", "$HOME/.aws", "$HOME/.config/gcloud", "$HOME/.kube", "$HOME/.docker"],
    "allowWrite": [".", "$AUTO_CLAUDE_HOME", "/tmp"],
    "denyWrite": [".env", "*.key", "*.pem", "*.secret", "credentials.json", "secrets.yaml"],
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
[ -n "$REQUEST" ] && echo "Request: $REQUEST"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Iteration $i of $MAX_ITERATIONS - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "==============================================================="

  LOG_FILE="$LOGS_DIR/iteration-$i-$(date '+%Y%m%d-%H%M%S').log"

  # Build optional request block (only first iteration)
  REQUEST_BLOCK=""
  if [ -n "$REQUEST" ]; then
    REQUEST_BLOCK="
USER REQUEST:
$REQUEST

Before starting the normal workflow, you MUST process this request:

1. READ CONTEXT: Read docs/spec.md, docs/architecture.md, and docs/current-state.md to understand the current system.

2. CLASSIFY the request as one of:
   a) BUG — something is broken or behaving incorrectly
   b) FEATURE — new functionality or a change to existing behavior
   c) GUIDANCE — instruction on approach (e.g. 'use WebGL2 instead of WebGL1')

3. ACT based on classification:

   FOR BUGS:
   - Investigate the root cause by reading relevant source files
   - Create ONE work item: python3 .claude/tools/tasks.py create 'Fix: <description>' '<root cause and fix approach>' --priority 1
   - Then proceed to STEP 1 (the new item will be picked up as next task)

   FOR FEATURES:
   - Update docs/spec.md with the new or changed requirements
   - Update docs/architecture.md if the design is affected
   - Break the feature into small work items (each completable in one session)
   - Add each item: python3 .claude/tools/tasks.py create '<title>' '<description>' --priority <N>
   - Set dependencies if needed: python3 .claude/tools/tasks.py update WI-XXX --deps WI-YYY
   - Then proceed to STEP 1 (tasks.py next will pick the first actionable item)

   FOR GUIDANCE:
   - Append the guidance to work/progress.txt under Codebase Patterns so all future sessions see it
   - Then proceed to STEP 1 (normal task flow, applying the guidance)

After processing, continue with the normal WORKFLOW below.
"
  fi

  # Comprehensive workflow prompt
  PROMPT="You are an autonomous coding agent. Follow EVERY step below. Do NOT skip any step.

PROJECT GOAL:
$PROJECT_GOAL
$REQUEST_BLOCK
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

  # Reset live stats for this iteration
  LIVE_STATS_FILE="$LOGS_DIR/live-stats.json"
  rm -f "$LIVE_STATS_FILE"

  # Start background watcher for real-time stats
  bash "$SCRIPT_DIR/scripts/watch-stats.sh" "$LIVE_STATS_FILE" 3 &
  WATCHER_PID=$!

  echo "Starting claude..."
  if [ "$USE_SANDBOX" = true ] && [ -n "$SANDBOX_CONFIG_FILE" ]; then
    OUTPUT=$(srt -s "$SANDBOX_CONFIG_FILE" -c "claude $MODEL_FLAG --chrome --dangerously-skip-permissions -p \"$PROMPT\"" 2>&1 | tee "$LOG_FILE") || true
  else
    OUTPUT=$(claude $MODEL_FLAG --chrome --dangerously-skip-permissions -p "$PROMPT" 2>&1 | tee "$LOG_FILE") || true
  fi

  # Kill watcher
  kill "$WATCHER_PID" 2>/dev/null; wait "$WATCHER_PID" 2>/dev/null
  echo ""
  echo "Claude exited. Log: $(wc -l < "$LOG_FILE") lines."

  # Print final stats summary for this iteration
  if [ -f "$LIVE_STATS_FILE" ]; then
    python3 -c "
import json
with open('$LIVE_STATS_FILE') as f:
    s = json.load(f)
ctx = s.get('context_pct', 0)
calls = s.get('tool_calls', 0)
modified = s.get('files_modified', [])
read_files = s.get('files_read', [])
print(f'  Summary: {ctx:.0f}% context | {calls} tool calls | {len(modified)} files modified | {len(read_files)} files read')
if modified:
    print(f'  Modified: {chr(10).join(\"    \" + f for f in modified)}')
" 2>/dev/null || true
  fi

  # Clear request after first iteration (only injected once)
  REQUEST=""

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
