# Auto Claude

An autonomous development framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Drop it into any project and let Claude work through tasks independently — planning, implementing, testing, scanning for security issues, and documenting as it goes.

## Requirements

- **Python 3.6+** (stdlib only, no external packages)
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)** installed and authenticated
- **Bash** and **Git**
- **[srt](https://github.com/AkimaLunar/srt)** (recommended) — sandbox runtime for filesystem/network isolation
- **Node.js** (optional) — for Playwright-based browser testing

## Quick Start

### New project

```bash
git clone https://github.com/snadeau123/auto_claude.git
cd auto_claude
.claude/loop.sh --init "Build a todo app with React and Express" --max-iterations 10
```

This will:
1. Generate `docs/spec.md`, `docs/architecture.md`, and `work/items.json` with small, dependency-ordered tasks
2. Start the autonomous loop, picking up and completing tasks one by one

### Continue an existing project

If the loop was interrupted or hit its iteration limit, just run it again:

```bash
.claude/loop.sh --max-iterations 10
```

It picks up where it left off — incomplete tasks resume automatically.

## Usage

```
.claude/loop.sh [OPTIONS]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--init "description"` | — | Initialize a new project: generates spec, architecture, and work items |
| `--max-iterations N` | 50 | Maximum loop iterations (recommended: set this to stay safe) |
| `--model MODEL` | — | Claude model to use (e.g. `opus`, `sonnet`) |
| `--sandbox` | on | Run inside srt sandbox (filesystem/network isolation) |
| `--request "text"` | — | Feature request, bug report, or guidance for the first iteration |
| `--no-sandbox` | — | Disable sandboxing |
| `-h, --help` | — | Show help and usage examples |

**Tip:** Always set `--max-iterations` to a reasonable number to avoid runaway sessions.

## How It Works

Each iteration spawns a fresh Claude instance that:

1. **Gets the next task** from `work/items.json`
2. **Reads project docs** — spec, architecture, current state
3. **Searches for related systems** via the memory tool before coding
4. **Implements** the feature or fix
5. **Tests** via Playwright browser automation or project test suite
6. **Security scans** for secrets, injection, OWASP issues
7. **Updates documentation** — current-state, architecture, per-feature docs
8. **Commits** with conventional commit messages
9. **Checks context usage** — continues if under 60%, stops if higher

If context runs out mid-task, it saves progress notes and the next iteration picks up cleanly.

## Tools

| Command | Purpose |
|---------|---------|
| `python3 .claude/tools/tasks.py next` | Get next task |
| `python3 .claude/tools/tasks.py list` | List all tasks |
| `python3 .claude/tools/tasks.py update <id> --status <s>` | Update task status |
| `python3 .claude/tools/tasks.py stats` | Completion statistics |
| `python3 .claude/tools/tasks.py reconcile` | Sync task status with git commits |
| `python3 .claude/tools/memory.py index` | Build TF-IDF search index over docs |
| `python3 .claude/tools/memory.py find "<query>"` | Semantic search across all docs |

## Skills

These are invoked automatically during the loop, or manually via `claude /skill-name`:

| Skill | Purpose |
|-------|---------|
| `/loop` | Execute one autonomous iteration |
| `/prd` | Generate spec, architecture, and work items from a description |
| `/functional-test` | Test the app using Playwright or Chrome MCP |
| `/playwright-test` | Direct Playwright browser automation |
| `/security-scan` | Scan for secrets, injection, OWASP Top 10 |
| `/doc-refresh` | Update project docs after implementing a feature |

## Project Structure

```
.claude/
├── loop.sh              # Main orchestration loop
├── CLAUDE.md            # Framework instructions for Claude
├── settings.json        # Permissions and hooks
├── tools/
│   ├── tasks.py         # Work item management (JSON-backed)
│   ├── memory.py        # TF-IDF doc search
│   └── context.py       # Context window usage tracking
├── skills/
│   ├── loop/            # Autonomous iteration
│   ├── prd/             # Project spec generator
│   ├── functional-test/ # Browser automation testing
│   ├── playwright-test/ # Playwright testing
│   ├── security-scan/   # Security scanner
│   └── doc-refresh/     # Documentation updater
├── hooks/
│   ├── context-usage.sh # PostToolUse context telemetry
│   ├── copy-session-log.sh # Copies session logs after each iteration
│   └── live-stats.sh     # Real-time stats collection (tool calls, files, context %)
└── scripts/
    └── watch-stats.sh    # Background watcher for live stats during iterations
```

## Sandbox

By default, iterations run inside [srt](https://github.com/AkimaLunar/srt) with:

- **Network**: Only allows GitHub, Anthropic API, PyPI, and npm registry
- **Filesystem**: Blocks reads to `~/.ssh`, `~/.gnupg`, `~/.aws`; blocks writes to `.env`, `*.key`, `*.pem`

Disable with `--no-sandbox` if srt is not installed or not needed.

## Authentication

The loop uses a dedicated config directory at `~/.auto_claude` to keep auth tokens separate from your main `~/.claude.json`. On first run, it will prompt you to set up a token via `claude setup-token`. This avoids conflicts with your regular Claude Code sessions.

## Acknowledgments

The Playwright testing skill is based on [playwright-skill](https://github.com/lackeyjb/playwright-skill) by [@lackeyjb](https://github.com/lackeyjb), licensed under MIT.

## License

MIT
