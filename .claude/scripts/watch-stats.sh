#!/bin/bash
# Background watcher: polls live-stats.json and prints a status line
# Usage: bash .claude/hooks/watch-stats.sh <stats-file> [poll-interval-seconds]
# Runs until killed by the parent loop.

STATS_FILE="$1"
INTERVAL="${2:-3}"
LAST_HASH=""

while true; do
  if [ -f "$STATS_FILE" ]; then
    HASH=$(md5sum "$STATS_FILE" 2>/dev/null | cut -d' ' -f1)
    if [ "$HASH" != "$LAST_HASH" ]; then
      LAST_HASH="$HASH"
      LINE=$(python3 -c "
import json, sys
try:
    with open('$STATS_FILE') as f:
        s = json.load(f)
    ctx = s.get('context_pct', 0)
    calls = s.get('tool_calls', 0)
    modified = s.get('files_modified', [])
    last = s.get('last_tool', '')
    mod_count = len(modified)
    mod_list = ', '.join(modified[-3:]) if modified else 'none'
    if mod_count > 3:
        mod_list = f'...+{mod_count-3} more, {mod_list}'
    tokens = s.get('tokens', 0)
    if tokens > 1000:
        tok_str = f'{tokens/1000:.0f}k'
    else:
        tok_str = str(tokens)
    print(f'  [{ctx:.0f}% ctx | {tok_str} tokens | {calls} tools | {mod_count} files modified: {mod_list} | last: {last}]')
except Exception as e:
    pass
" 2>/dev/null)
      if [ -n "$LINE" ]; then
        echo -e "\r\033[K$LINE"
      fi
    fi
  fi
  sleep "$INTERVAL"
done
