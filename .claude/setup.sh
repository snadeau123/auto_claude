#!/bin/bash
# Setup script for .claude directory
# - Converts relative hook paths to absolute paths in settings.json
# - Updates sandbox config in loop.sh with local IP
# Run this after moving the project or on first setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/settings.json"
LOOP_FILE="$SCRIPT_DIR/loop.sh"

echo "========================================"
echo "  Claude Project Setup"
echo "========================================"
echo "Project root: $PROJECT_ROOT"
echo ""

# --- 1. Detect local IP ---
echo "Step 1: Detecting local IP..."
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
  # Fallback for macOS
  LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
fi
if [ -z "$LOCAL_IP" ]; then
  LOCAL_IP="192.168.1.118"  # Default fallback
  echo "  Warning: Could not detect IP, using default: $LOCAL_IP"
else
  echo "  Detected IP: $LOCAL_IP"
fi

# --- 2. Update loop.sh sandbox config with local IP ---
echo ""
echo "Step 2: Updating loop.sh sandbox config..."
if [ -f "$LOOP_FILE" ]; then
  # Replace any IP in the 192.168.x.x range or the placeholder with detected IP
  if grep -q '"localhost", "127.0.0.1"' "$LOOP_FILE"; then
    # Check if there's already an IP after 127.0.0.1
    if grep -q '"localhost", "127.0.0.1", "192\.' "$LOOP_FILE"; then
      # Replace existing IP
      sed -i "s/\"localhost\", \"127.0.0.1\", \"192\.[0-9.]*\"/\"localhost\", \"127.0.0.1\", \"$LOCAL_IP\"/" "$LOOP_FILE"
      echo "  Updated sandbox IP to: $LOCAL_IP"
    else
      # Add IP after 127.0.0.1
      sed -i "s/\"localhost\", \"127.0.0.1\"/\"localhost\", \"127.0.0.1\", \"$LOCAL_IP\"/" "$LOOP_FILE"
      echo "  Added sandbox IP: $LOCAL_IP"
    fi
  else
    echo "  Warning: Could not find sandbox config pattern in loop.sh"
  fi
else
  echo "  Warning: loop.sh not found at $LOOP_FILE"
fi

# --- 3. Update settings.json with absolute hook paths ---
echo ""
echo "Step 3: Updating settings.json hook paths..."
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "  Error: settings.json not found at $SETTINGS_FILE"
  exit 1
fi

python3 << EOF
import json
import re
import sys

settings_file = "$SETTINGS_FILE"
project_root = "$PROJECT_ROOT"

with open(settings_file, 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
changes = 0

def fix_command(cmd):
    """Replace relative .claude/ paths with absolute paths."""
    global changes
    old_cmd = cmd

    # First, remove any existing absolute path prefix to normalize
    # Match patterns like /some/old/path/.claude/ and replace with .claude/
    cmd = re.sub(r'/[^\s]+/\.claude/', '.claude/', cmd)

    # Now replace relative .claude/ with absolute path
    if '.claude/' in cmd:
        cmd = cmd.replace('.claude/', f'{project_root}/.claude/')
        if cmd != old_cmd:
            changes += 1
            print(f"  Fixed: {old_cmd[:50]}...")
            print(f"      -> {cmd[:50]}...")

    return cmd

# Process all hooks
for event_type, matchers in hooks.items():
    for matcher in matchers:
        for hook in matcher.get('hooks', []):
            if hook.get('type') == 'command':
                hook['command'] = fix_command(hook['command'])

if changes > 0:
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print(f"  Updated {changes} hook command(s).")
else:
    print("  No changes needed - hooks already use absolute paths.")
EOF

# --- 4. Clear auto_claude todos to prevent migration bugs ---
echo ""
echo "Step 4: Clearing auto_claude todos..."
AUTO_CLAUDE_TODOS="$HOME/.auto_claude/todos"
if [ -d "$AUTO_CLAUDE_TODOS" ]; then
  TODO_COUNT=$(ls -1 "$AUTO_CLAUDE_TODOS"/*.json 2>/dev/null | wc -l)
  rm -f "$AUTO_CLAUDE_TODOS"/*.json 2>/dev/null
  echo "  Cleared $TODO_COUNT todo files (prevents TodoWrite migration bug)"
else
  echo "  No todos directory found"
fi

echo ""
echo "========================================"
echo "  Setup complete!"
echo "========================================"
echo ""
echo "You can now run: .claude/loop.sh"
