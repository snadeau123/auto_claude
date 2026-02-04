#!/bin/bash
# Watchdog: kills a process tree if a file stops being updated
# Usage: watchdog.sh <pid> <watch-file> <timeout-seconds> [session-id]

PID="$1"
WATCH_FILE="$2"
TIMEOUT="${3:-300}"  # Default 5 minutes
SESSION_ID="$4"      # Optional: to filter which session we're watching

if [ -z "$PID" ] || [ -z "$WATCH_FILE" ]; then
  echo "Usage: watchdog.sh <pid> <watch-file> [timeout-seconds] [session-id]"
  exit 1
fi

LAST_MTIME=0
STALL_START=0

# Function to kill entire process tree
kill_tree() {
  local target_pid=$1
  echo "[WATCHDOG] Killing process tree rooted at $target_pid"

  # ALWAYS kill any claude -p processes first (srt creates complex hierarchy)
  pkill -9 -f "claude.*--dangerously-skip-permissions" 2>/dev/null

  # Kill srt processes
  pkill -9 -f "srt.*claude" 2>/dev/null

  # Kill orphaned watch-stats processes
  pkill -9 -f "watch-stats.sh" 2>/dev/null

  # Kill by process group if possible
  pkill -9 -g "$target_pid" 2>/dev/null

  # Also kill any child processes recursively
  for child in $(pgrep -P "$target_pid" 2>/dev/null); do
    kill_tree "$child"
  done

  # Kill the target itself
  kill -9 "$target_pid" 2>/dev/null
}

while kill -0 "$PID" 2>/dev/null; do
  # Get file modification time (seconds since epoch)
  if [ -f "$WATCH_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$WATCH_FILE" 2>/dev/null || echo "0")

    # If session ID provided, check the file contains our session
    if [ -n "$SESSION_ID" ] && [ -f "$WATCH_FILE" ]; then
      if ! grep -q "$SESSION_ID" "$WATCH_FILE" 2>/dev/null; then
        # File doesn't contain our session - might be another session updating it
        # Don't reset the stall timer
        CURRENT_MTIME="$LAST_MTIME"
      fi
    fi
  else
    CURRENT_MTIME=0
  fi

  NOW=$(date +%s)

  if [ "$CURRENT_MTIME" != "$LAST_MTIME" ] && [ "$CURRENT_MTIME" != "0" ]; then
    # File was updated (by our session), reset stall timer
    LAST_MTIME="$CURRENT_MTIME"
    STALL_START=0
  else
    # File not updated
    if [ "$STALL_START" -eq 0 ]; then
      STALL_START="$NOW"
    else
      STALL_DURATION=$((NOW - STALL_START))
      if [ "$STALL_DURATION" -ge "$TIMEOUT" ]; then
        echo "[WATCHDOG] No activity for ${STALL_DURATION}s - killing process tree"
        kill_tree "$PID"
        exit 1
      fi
    fi
  fi

  sleep 10
done

# Process exited normally
exit 0
