#!/bin/bash
# PostToolUse hook: feeds context usage from both sources back to Claude
# 1. Statusline telemetry (accurate but only in interactive mode)
# 2. Transcript calculation (always available, may overcount)

python3 -c "
import json, os, sys

data = json.load(sys.stdin)
session_id = data.get('session_id', '')
transcript_path = data.get('transcript_path', '')
cwd = data.get('cwd', '')

if not session_id:
    sys.exit(0)

telemetry_used = 0
transcript_used = 0

# Source 1: statusline-written metrics file
metrics_file = os.path.join(cwd, '.claude', 'context-metrics.json')
if os.path.exists(metrics_file):
    try:
        with open(metrics_file) as f:
            metrics = json.load(f)
        entry = metrics.get(session_id, {})
        telemetry_used = entry.get('used_percentage', 0)
    except Exception:
        pass

# Source 2: calculate from transcript (only read last 50KB)
if transcript_path and os.path.exists(transcript_path):
    try:
        file_size = os.path.getsize(transcript_path)
        with open(transcript_path, 'rb') as f:
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
                    u = obj['message']['usage']
                    if all(k in u for k in ['input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens', 'output_tokens']):
                        tokens = u['input_tokens'] + u['cache_creation_input_tokens'] + u['cache_read_input_tokens'] + u['output_tokens']
                        transcript_used = (tokens / 200000) * 100
                        break
            except json.JSONDecodeError:
                continue
    except Exception:
        pass

parts = []
if telemetry_used > 0:
    parts.append(f'telemetry:{telemetry_used:.0f}%')
if transcript_used > 0:
    parts.append(f'estimation from transcript:{transcript_used:.0f}%')

if parts:
    msg = '[Context ' + ' | ' .join(parts) + ']'
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PostToolUse',
            'additionalContext': msg
        }
    }))
"

exit 0
