#!/bin/bash
# Stop hook: copies the session transcript into the project's work/logs/ directory
# This gives the loop persistent access to what each iteration did.

python3 -c "
import json, sys, os, shutil
from datetime import datetime

data = json.load(sys.stdin)
session_id = data.get('session_id', '')
transcript_path = data.get('transcript_path', '')
cwd = data.get('cwd', '')

if not transcript_path or not os.path.exists(transcript_path):
    sys.exit(0)

logs_dir = os.path.join(cwd, 'work', 'logs')
os.makedirs(logs_dir, exist_ok=True)

timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
short_id = session_id[:8] if session_id else 'unknown'
dest = os.path.join(logs_dir, f'session-{timestamp}-{short_id}.jsonl')

shutil.copy2(transcript_path, dest)
"

exit 0
