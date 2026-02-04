#!/bin/bash
# PostToolUse hook: writes live session stats to work/logs/live-stats.json
# A background watcher in loop.sh reads this file to display real-time progress.

python3 -c "
import json, sys, os
from datetime import datetime

data = json.load(sys.stdin)
session_id = data.get('session_id', '')
transcript_path = data.get('transcript_path', '')
cwd = data.get('cwd', '')
tool_name = data.get('tool_name', '')
tool_input = data.get('tool_input', {})

if not cwd:
    sys.exit(0)

stats_file = os.path.join(cwd, 'work', 'logs', 'live-stats.json')
os.makedirs(os.path.dirname(stats_file), exist_ok=True)

# Load existing stats or create new
stats = {}
if os.path.exists(stats_file):
    try:
        with open(stats_file) as f:
            stats = json.load(f)
    except Exception:
        stats = {}

# Reset if new session
if stats.get('session_id') != session_id:
    stats = {
        'session_id': session_id,
        'started': datetime.now().isoformat(),
        'tool_calls': 0,
        'tokens': 0,
        'context_pct': 0,
        'files_modified': [],
        'files_read': [],
        'last_tool': '',
        'last_update': ''
    }

stats['tool_calls'] = stats.get('tool_calls', 0) + 1
stats['last_tool'] = tool_name
stats['last_update'] = datetime.now().isoformat()

# Track file modifications
file_path = tool_input.get('file_path', '')
if file_path:
    # Strip cwd prefix for readability
    rel = os.path.relpath(file_path, cwd) if file_path.startswith(cwd) else file_path

    if tool_name in ('Edit', 'Write'):
        modified = stats.get('files_modified', [])
        if rel not in modified:
            modified.append(rel)
        stats['files_modified'] = modified

    elif tool_name == 'Read':
        read_files = stats.get('files_read', [])
        if rel not in read_files:
            read_files.append(rel)
        stats['files_read'] = read_files

# Extract token usage from transcript (last assistant message)
# Only read last 50KB to avoid loading huge files
if transcript_path and os.path.exists(transcript_path):
    try:
        last_usage = None
        file_size = os.path.getsize(transcript_path)
        with open(transcript_path, 'rb') as f:
            # Seek to last 50KB (enough to find recent messages)
            f.seek(max(0, file_size - 50000))
            chunk = f.read().decode('utf-8', errors='ignore')
        for line in reversed(chunk.split('\\n')):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if (obj.get('type') == 'assistant'
                    and 'message' in obj
                    and 'usage' in obj['message']):
                    last_usage = obj['message']['usage']
                    break
            except (json.JSONDecodeError, KeyError):
                continue
        if last_usage:
            tokens = (last_usage.get('input_tokens', 0)
                    + last_usage.get('cache_creation_input_tokens', 0)
                    + last_usage.get('cache_read_input_tokens', 0)
                    + last_usage.get('output_tokens', 0))
            stats['tokens'] = tokens
            stats['context_pct'] = round((tokens / 200000) * 100, 1)
    except Exception:
        pass

with open(stats_file, 'w') as f:
    json.dump(stats, f)
"

exit 0
