#!/usr/bin/env python3
"""Context metrics tool - reads context window usage from metrics file."""
import json
import os
import sys

METRICS_FILE = os.path.join(os.path.dirname(__file__), '..', 'context-metrics.json')


def show(session_id=None):
    """Show context metrics, optionally filtered to a session."""
    if not os.path.exists(METRICS_FILE):
        print("No context metrics recorded yet.")
        return

    with open(METRICS_FILE, 'r') as f:
        data = json.load(f)

    if session_id:
        entry = data.get(session_id)
        if not entry:
            print(f"No metrics for session {session_id}")
            return
        print_entry(session_id, entry)
    else:
        # Show all sessions, most recent first
        entries = sorted(data.items(), key=lambda x: x[1].get('timestamp', ''), reverse=True)
        for sid, entry in entries:
            print_entry(sid, entry)
            print()


def print_entry(session_id, entry):
    used = entry.get('used_percentage', 0)
    remaining = entry.get('remaining_percentage', 100)
    size = entry.get('context_window_size', 0)
    model = entry.get('model', 'unknown')
    ts = entry.get('timestamp', '')
    total_in = entry.get('total_input_tokens', 0)
    total_out = entry.get('total_output_tokens', 0)

    print(f"Session:   {session_id}")
    print(f"Model:     {model}")
    print(f"Used:      {used:.1f}% ({int(size * used / 100):,} / {size:,} tokens)")
    print(f"Remaining: {remaining:.1f}%")
    print(f"Totals:    {total_in:,} in / {total_out:,} out")
    print(f"Updated:   {ts}")


if __name__ == '__main__':
    sid = sys.argv[1] if len(sys.argv) > 1 else None
    show(sid)
