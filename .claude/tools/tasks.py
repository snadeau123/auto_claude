#!/usr/bin/env python3
"""
Tasks Tool - Work item management for Auto Claude

CRUD operations for work items in work/items.json.

Usage:
    python3 tasks.py list [--status pending|in_progress|completed|blocked]
    python3 tasks.py get <id>
    python3 tasks.py next                    # Get next actionable item
    python3 tasks.py create <title> <description> [--priority N] [--deps ID,ID]
    python3 tasks.py update <id> --status <status>
    python3 tasks.py update <id> --notes "note text"
    python3 tasks.py update <id> --title "new title"
    python3 tasks.py stats                   # Show completion statistics
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
ITEMS_FILE = PROJECT_ROOT / "work" / "items.json"


def load_items():
    """Load items from JSON file. Handles both array and object formats."""
    if not ITEMS_FILE.exists():
        return {"project": "auto_claude", "branchName": "main", "workItems": []}
    with open(ITEMS_FILE) as f:
        data = json.load(f)
    # Normalize: if it's a plain array, wrap it
    if isinstance(data, list):
        return {"project": "unknown", "branchName": "main", "workItems": data}
    return data


def save_items(data):
    """Save items to JSON file."""
    ITEMS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(ITEMS_FILE, 'w') as f:
        json.dump(data, f, indent=2)


def get_next_id(items):
    """Generate next work item ID."""
    if not items:
        return "WI-001"
    max_num = max(int(item["id"].split("-")[1]) for item in items)
    return f"WI-{max_num + 1:03d}"


def is_actionable(item, all_items):
    """Check if item can be worked on (no unmet dependencies)."""
    if item["status"] != "pending":
        return False
    deps = item.get("dependencies", [])
    if not deps:
        return True
    completed_ids = {i["id"] for i in all_items if i["status"] == "completed"}
    return all(dep in completed_ids for dep in deps)


# =============================================================================
# Commands
# =============================================================================

def cmd_list(args):
    """List work items."""
    data = load_items()
    items = data.get("workItems", [])

    if args.status:
        items = [i for i in items if i["status"] == args.status]

    if not items:
        print(f"No items found{' with status ' + args.status if args.status else ''}.")
        return

    # Group by status
    by_status = {}
    for item in items:
        status = item["status"]
        if status not in by_status:
            by_status[status] = []
        by_status[status].append(item)

    status_order = ["in_progress", "pending", "blocked", "completed"]

    for status in status_order:
        if status in by_status:
            print(f"\n## {status.upper()} ({len(by_status[status])})")
            for item in by_status[status]:
                deps = item.get("dependencies", [])
                deps_str = f" [needs: {', '.join(deps)}]" if deps and status == "pending" else ""
                print(f"  {item['id']}: {item['title']}{deps_str}")


def cmd_get(args):
    """Get detailed info about a specific item."""
    data = load_items()
    items = data.get("workItems", [])

    item = next((i for i in items if i["id"] == args.id), None)
    if not item:
        print(f"Item {args.id} not found.")
        sys.exit(1)

    print(f"## {item['id']}: {item['title']}")
    print(f"Status: {item['status']}")
    print(f"Priority: {item.get('priority', 'N/A')}")

    deps = item.get("dependencies", [])
    if deps:
        print(f"Dependencies: {', '.join(deps)}")

    print(f"\n### Description\n{item.get('description', 'No description')}")

    criteria = item.get("acceptanceCriteria", [])
    if criteria:
        print("\n### Acceptance Criteria")
        for c in criteria:
            print(f"  - [ ] {c}")

    notes = item.get("notes", "")
    if notes:
        print(f"\n### Notes\n{notes}")


def cmd_next(args):
    """Get the next actionable work item."""
    data = load_items()
    items = data.get("workItems", [])

    # First check for in_progress items
    in_progress = [i for i in items if i["status"] == "in_progress"]
    if in_progress:
        item = in_progress[0]
        print(f"## Continue: {item['id']}: {item['title']}")
        print(f"\n{item.get('description', '')}")
        return

    # Find next actionable pending item
    actionable = [i for i in items if is_actionable(i, items)]
    if not actionable:
        # Check if all done
        pending = [i for i in items if i["status"] in ["pending", "blocked"]]
        if not pending:
            print("ALL ITEMS COMPLETED!")
            print("<promise>COMPLETE</promise>")
        else:
            print("No actionable items. Blocked items:")
            for i in [x for x in items if x["status"] == "blocked"]:
                print(f"  {i['id']}: {i['title']} - {i.get('notes', 'no notes')}")
        return

    # Sort by priority
    actionable.sort(key=lambda x: x.get("priority", 999))
    item = actionable[0]

    print(f"## Next: {item['id']}: {item['title']}")
    print(f"Priority: {item.get('priority', 'N/A')}")
    print(f"\n### Description\n{item.get('description', '')}")

    criteria = item.get("acceptanceCriteria", [])
    if criteria:
        print("\n### Acceptance Criteria")
        for c in criteria:
            print(f"  - [ ] {c}")


def cmd_create(args):
    """Create a new work item."""
    data = load_items()
    items = data.get("workItems", [])

    new_id = get_next_id(items)

    new_item = {
        "id": new_id,
        "title": args.title,
        "description": args.description,
        "acceptanceCriteria": [],
        "priority": args.priority or (max((i.get("priority", 0) for i in items), default=0) + 1),
        "status": "pending",
        "dependencies": args.deps.split(",") if args.deps else [],
        "notes": ""
    }

    items.append(new_item)
    data["workItems"] = items
    save_items(data)

    print(f"Created {new_id}: {args.title}")


def cmd_init(args):
    """Initialize work items from JSON array (stdin or file)."""
    import sys

    # Read JSON from stdin or file
    if args.file:
        with open(args.file) as f:
            raw = json.load(f)
    else:
        raw = json.load(sys.stdin)

    # Handle both array and object input
    if isinstance(raw, dict) and "workItems" in raw:
        items = raw["workItems"]
    elif isinstance(raw, list):
        items = raw
    else:
        print("Error: Expected JSON array or object with 'workItems' key")
        sys.exit(1)

    # Normalize each item
    normalized = []
    for i, item in enumerate(items):
        normalized.append({
            "id": item.get("id", f"WI-{i+1:03d}"),
            "title": item.get("title", "Untitled"),
            "description": item.get("description", ""),
            "acceptanceCriteria": item.get("acceptanceCriteria", []),
            "priority": item.get("priority", i + 1),
            "status": item.get("status", "pending"),
            "dependencies": item.get("dependencies", []),
            "notes": item.get("notes", "")
        })

    # Wrap in proper structure
    data = {
        "project": args.project,
        "branchName": args.branch or "main",
        "workItems": normalized
    }

    save_items(data)
    print(f"Initialized {len(normalized)} work items for project '{args.project}'")
    for item in normalized:
        print(f"  {item['id']}: {item['title']}")


def cmd_update(args):
    """Update a work item."""
    data = load_items()
    items = data.get("workItems", [])

    item = next((i for i in items if i["id"] == args.id), None)
    if not item:
        print(f"Item {args.id} not found.")
        sys.exit(1)

    updated = []

    if args.status:
        old_status = item["status"]
        item["status"] = args.status
        updated.append(f"status: {old_status} -> {args.status}")

        if args.status == "completed":
            item["notes"] = (item.get("notes", "") + f"\nCompleted {datetime.now().strftime('%Y-%m-%d %H:%M')}").strip()

    if args.notes:
        item["notes"] = args.notes
        updated.append("notes updated")

    if args.title:
        item["title"] = args.title
        updated.append(f"title: {args.title}")

    if args.add_criteria:
        if "acceptanceCriteria" not in item:
            item["acceptanceCriteria"] = []
        item["acceptanceCriteria"].append(args.add_criteria)
        updated.append(f"added criterion")

    if args.deps:
        item["dependencies"] = [d.strip() for d in args.deps.split(",")]
        updated.append(f"dependencies: {item['dependencies']}")

    save_items(data)
    print(f"Updated {args.id}: {', '.join(updated)}")


def cmd_reconcile(args):
    """Reconcile task status with git commits.

    Scans git log for commits matching 'feat(WI-XXX):' or 'docs(WI-XXX):'
    and marks those tasks as completed if they aren't already.
    Also resets any in_progress tasks back to pending (stale from crashed iterations).
    """
    import subprocess

    data = load_items()
    items = data.get("workItems", [])
    changed = []

    # Get all commit messages
    try:
        result = subprocess.run(
            ["git", "log", "--oneline", "--all"],
            capture_output=True, text=True, cwd=str(PROJECT_ROOT)
        )
        commit_log = result.stdout
    except Exception:
        commit_log = ""

    # Find WI-XXX references in commits
    import re
    committed_ids = set(re.findall(r'\b(WI-\d{3})\b', commit_log))

    for item in items:
        # Auto-complete tasks that have git commits
        if item["status"] in ("pending", "in_progress") and item["id"] in committed_ids:
            old = item["status"]
            item["status"] = "completed"
            item["notes"] = (item.get("notes", "") + f"\nAuto-completed by reconcile (found git commit) {datetime.now().strftime('%Y-%m-%d %H:%M')}").strip()
            changed.append(f"{item['id']}: {old} -> completed (git commit found)")

        # Reset stale in_progress back to pending (crashed iteration)
        elif item["status"] == "in_progress" and item["id"] not in committed_ids:
            item["status"] = "pending"
            item["notes"] = (item.get("notes", "") + f"\nReset to pending by reconcile {datetime.now().strftime('%Y-%m-%d %H:%M')}").strip()
            changed.append(f"{item['id']}: in_progress -> pending (no commit found)")

    if changed:
        save_items(data)
        print("## Reconciled Tasks")
        for c in changed:
            print(f"  - {c}")
    else:
        print("All tasks in sync with git history.")


def cmd_stats(args):
    """Show completion statistics."""
    data = load_items()
    items = data.get("workItems", [])

    total = len(items)
    if total == 0:
        print("No work items.")
        return

    by_status = {}
    for item in items:
        status = item["status"]
        by_status[status] = by_status.get(status, 0) + 1

    completed = by_status.get("completed", 0)
    in_progress = by_status.get("in_progress", 0)
    pending = by_status.get("pending", 0)
    blocked = by_status.get("blocked", 0)

    print("## Work Item Statistics")
    print(f"Total: {total}")
    print(f"Completed: {completed} ({100*completed//total}%)")
    print(f"In Progress: {in_progress}")
    print(f"Pending: {pending}")
    print(f"Blocked: {blocked}")

    if completed < total:
        actionable = len([i for i in items if is_actionable(i, items)])
        print(f"\nActionable now: {actionable}")


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Work item management")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # list
    list_p = subparsers.add_parser("list", help="List work items")
    list_p.add_argument("--status", choices=["pending", "in_progress", "completed", "blocked"])

    # get
    get_p = subparsers.add_parser("get", help="Get item details")
    get_p.add_argument("id", help="Item ID (e.g., WI-001)")

    # next
    subparsers.add_parser("next", help="Get next actionable item")

    # create
    create_p = subparsers.add_parser("create", help="Create new item")
    create_p.add_argument("title", help="Item title")
    create_p.add_argument("description", help="Item description")
    create_p.add_argument("--priority", type=int, help="Priority (lower = higher)")
    create_p.add_argument("--deps", help="Comma-separated dependency IDs")

    # init
    init_p = subparsers.add_parser("init", help="Initialize items from JSON array")
    init_p.add_argument("project", help="Project name")
    init_p.add_argument("--branch", help="Branch name (default: main)")
    init_p.add_argument("--file", "-f", help="Read from file instead of stdin")

    # update
    update_p = subparsers.add_parser("update", help="Update item")
    update_p.add_argument("id", help="Item ID")
    update_p.add_argument("--status", choices=["pending", "in_progress", "completed", "blocked"])
    update_p.add_argument("--notes", help="Set notes")
    update_p.add_argument("--title", help="Set title")
    update_p.add_argument("--add-criteria", help="Add acceptance criterion")
    update_p.add_argument("--deps", help="Set comma-separated dependency IDs")

    # stats
    subparsers.add_parser("stats", help="Show statistics")

    # reconcile
    subparsers.add_parser("reconcile", help="Sync task status with git commits")

    args = parser.parse_args()

    commands = {
        "list": cmd_list,
        "get": cmd_get,
        "next": cmd_next,
        "create": cmd_create,
        "init": cmd_init,
        "update": cmd_update,
        "stats": cmd_stats,
        "reconcile": cmd_reconcile,
    }

    if args.command in commands:
        commands[args.command](args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
