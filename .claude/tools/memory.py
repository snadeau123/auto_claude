#!/usr/bin/env python3
"""
RLM-Inspired Memory Tool - Navigate large documentation sets

Based on Recursive Language Models (RLM) paper concepts:
- Treat large context as external environment variable
- Programmatic access: peek, slice, filter, chunk
- TF-IDF semantic search to narrow search space
- Batched queries across chunks

For basic file reading (goal, README, small docs), use Claude's native Read tool.
This tool is for documentation too large to fit in context.

Usage:
    python3 memory.py index [--path DIR]           # Build searchable index
    python3 memory.py find "<query>" [--top N]     # TF-IDF semantic search
    python3 memory.py peek <file> [--lines N]      # Preview first N lines
    python3 memory.py chunk <file> [--by sections|lines] [--size N]
    python3 memory.py topics                       # List all indexed sections
    python3 memory.py stats                        # Index statistics
    python3 memory.py batch "<query>" --files f1,f2,f3  # Search specific files
"""

import argparse
import json
import math
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Optional

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
DOCS_DIR = PROJECT_ROOT / "docs"
WORK_DIR = PROJECT_ROOT / "work"
INDEX_FILE = WORK_DIR / ".doc-index.json"

# Extensions to index
INDEXABLE = ['.md', '.txt', '.rst', '.py', '.js', '.ts', '.json']

# Stopwords for TF-IDF
STOPWORDS = {
    'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were',
    'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did',
    'will', 'would', 'could', 'should', 'may', 'might', 'must', 'shall',
    'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from', 'as',
    'into', 'through', 'during', 'before', 'after', 'above', 'below',
    'this', 'that', 'these', 'those', 'it', 'its', 'they', 'them',
    'we', 'you', 'i', 'he', 'she', 'what', 'which', 'who', 'when',
    'where', 'why', 'how', 'all', 'each', 'every', 'both', 'few',
    'more', 'most', 'other', 'some', 'such', 'no', 'not', 'only',
    'own', 'same', 'so', 'than', 'too', 'very', 'just', 'can', 'if'
}


def tokenize(text: str) -> list[str]:
    """Extract searchable tokens from text (RLM-style filtering)."""
    tokens = re.findall(r'\b[a-z][a-z0-9_]+\b', text.lower())
    return [t for t in tokens if t not in STOPWORDS and len(t) > 2]


def extract_sections(content: str, filepath: str) -> list[dict]:
    """Extract sections with headers from markdown content."""
    sections = []
    lines = content.split('\n')

    current_header = filepath
    current_content = []
    header_stack = []
    current_line_start = 0

    for i, line in enumerate(lines):
        header_match = re.match(r'^(#{1,4})\s+(.+)$', line)
        if header_match:
            if current_content:
                text = '\n'.join(current_content).strip()
                if text:
                    sections.append({
                        'header': current_header,
                        'hierarchy': ' > '.join(header_stack) if header_stack else '',
                        'content': text,
                        'tokens': tokenize(text + ' ' + current_header),
                        'line_start': current_line_start,
                        'line_end': i
                    })

            level = len(header_match.group(1))
            header_text = header_match.group(2).strip()
            current_header = header_text

            while header_stack and len(header_stack) >= level:
                header_stack.pop()
            header_stack.append(header_text)

            current_content = []
            current_line_start = i + 1
        else:
            current_content.append(line)

    if current_content:
        text = '\n'.join(current_content).strip()
        if text:
            sections.append({
                'header': current_header,
                'hierarchy': ' > '.join(header_stack) if header_stack else '',
                'content': text,
                'tokens': tokenize(text + ' ' + current_header),
                'line_start': current_line_start,
                'line_end': len(lines)
            })

    return sections


def get_indexable_files(search_path: Optional[Path] = None) -> list[Path]:
    """Find all indexable files in the search path."""
    if search_path is None:
        search_dirs = [DOCS_DIR, WORK_DIR, PROJECT_ROOT]
    else:
        search_dirs = [search_path]

    files = []
    for search_dir in search_dirs:
        if not search_dir.exists():
            continue
        for ext in INDEXABLE:
            for path in search_dir.rglob(f'*{ext}'):
                # Skip common excludes
                path_str = str(path)
                if any(x in path_str for x in ['node_modules', '.git', '__pycache__', 'archive']):
                    continue
                # For project root, only include root-level files
                if search_dir == PROJECT_ROOT and path.parent != PROJECT_ROOT:
                    if DOCS_DIR not in path.parents and WORK_DIR not in path.parents:
                        continue
                files.append(path)

    return files


def build_index(search_path: Optional[Path] = None) -> dict:
    """Build searchable index of all documentation (RLM-style context indexing)."""
    index = {
        'created': datetime.now().isoformat(),
        'root': str(search_path or PROJECT_ROOT),
        'files': [],
        'sections': [],
        'idf': {},
        'total_tokens': 0,
        'total_chars': 0
    }

    files = get_indexable_files(search_path)
    all_sections = []

    for path in files:
        try:
            content = path.read_text()
            try:
                rel_path = str(path.relative_to(search_path or PROJECT_ROOT))
            except ValueError:
                rel_path = str(path)

            index['files'].append({
                'path': rel_path,
                'size': len(content),
                'lines': content.count('\n') + 1,
                'tokens': len(tokenize(content))
            })
            index['total_chars'] += len(content)

            # Extract sections for markdown files
            if path.suffix in ['.md', '.txt', '.rst']:
                sections = extract_sections(content, rel_path)
            else:
                # For code files, treat as single section
                sections = [{
                    'header': rel_path,
                    'hierarchy': '',
                    'content': content[:2000],  # Preview only
                    'tokens': tokenize(content),
                    'line_start': 0,
                    'line_end': content.count('\n') + 1
                }]

            for section in sections:
                section['file'] = rel_path
                all_sections.append(section)
                index['total_tokens'] += len(section['tokens'])

        except Exception as e:
            print(f"Warning: Could not index {path}: {e}", file=sys.stderr)

    index['sections'] = all_sections

    # Compute IDF (inverse document frequency) for TF-IDF search
    doc_count = len(all_sections)
    if doc_count > 0:
        df = Counter()
        for section in all_sections:
            for term in set(section['tokens']):
                df[term] += 1

        index['idf'] = {
            term: math.log(doc_count / count)
            for term, count in df.items()
            if count < doc_count  # Exclude terms in all docs
        }

    return index


def load_index() -> dict | None:
    """Load existing index."""
    if INDEX_FILE.exists():
        try:
            return json.loads(INDEX_FILE.read_text())
        except:
            return None
    return None


def save_index(index: dict):
    """Save index to disk."""
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    # Don't save full content to keep index small
    compact = {k: v for k, v in index.items() if k != 'sections'}
    compact['sections'] = [
        {k: v for k, v in s.items() if k != 'content'}
        for s in index['sections']
    ]
    INDEX_FILE.write_text(json.dumps(compact, indent=2))


def search_index(index: dict, query: str, top_n: int = 10, files: list[str] = None) -> list[dict]:
    """TF-IDF semantic search across indexed sections."""
    query_tokens = tokenize(query)
    if not query_tokens:
        return []

    results = []
    idf = index.get('idf', {})

    for section in index.get('sections', []):
        # Filter by files if specified
        if files and section['file'] not in files:
            continue

        tf = Counter(section['tokens'])
        total = len(section['tokens']) if section['tokens'] else 1

        score = 0
        matched_terms = []
        for term in query_tokens:
            if term in tf:
                term_score = (tf[term] / total) * idf.get(term, 1)
                score += term_score
                matched_terms.append(term)

        if score > 0:
            results.append({
                'file': section['file'],
                'header': section['header'],
                'hierarchy': section.get('hierarchy', ''),
                'score': score,
                'matched': matched_terms,
                'line_start': section.get('line_start', 0),
                'line_end': section.get('line_end', 0),
                'content': section.get('content', '')[:300]
            })

    results.sort(key=lambda x: x['score'], reverse=True)
    return results[:top_n]


# =============================================================================
# Commands
# =============================================================================

def cmd_index(args):
    """Build documentation index (RLM: load context as environment variable)."""
    search_path = Path(args.path) if args.path else None

    print("Building documentation index...")
    index = build_index(search_path)
    save_index(index)

    print(f"\n## Index Built\n")
    print(f"Files: {len(index['files'])}")
    print(f"Sections: {len(index['sections'])}")
    print(f"Total chars: {index['total_chars']:,}")
    print(f"Total tokens: {index['total_tokens']:,}")
    print(f"Unique terms (IDF): {len(index['idf'])}")
    print()

    if index['files']:
        print("### Indexed Files")
        for f in sorted(index['files'], key=lambda x: -x['size'])[:15]:
            print(f"  {f['path']} ({f['lines']} lines, {f['tokens']} tokens)")
        if len(index['files']) > 15:
            print(f"  ... and {len(index['files']) - 15} more")

    print(f"\nIndex saved to: {INDEX_FILE.relative_to(PROJECT_ROOT)}")


def cmd_find(args):
    """TF-IDF semantic search (RLM: filter context using model priors)."""
    index = load_index()
    if not index:
        print("No index found. Run: python3 memory.py index")
        sys.exit(1)

    # Re-load full index with content
    full_index = build_index(Path(index['root']) if index.get('root') else None)

    files = args.files.split(',') if args.files else None
    results = search_index(full_index, args.query, args.top or 5, files)

    if not results:
        print(f"No matches for: {args.query}")
        print("\nTry different keywords or run 'memory.py index' to rebuild.")
        return

    print(f"## Search: '{args.query}'\n")

    for i, r in enumerate(results, 1):
        print(f"### {i}. {r['file']}:{r['line_start']}")
        if r['header'] != r['file']:
            print(f"Section: {r['header']}")
        print(f"Score: {r['score']:.3f} | Matched: {', '.join(r['matched'])}")
        if r['content']:
            preview = r['content'].replace('\n', ' ')[:200]
            print(f"\n> {preview}...")
        print()


def cmd_peek(args):
    """Preview first N lines of a file (RLM: peek into context)."""
    path = PROJECT_ROOT / args.file
    if not path.exists():
        # Try as absolute
        path = Path(args.file)
    if not path.exists():
        print(f"File not found: {args.file}")
        sys.exit(1)

    lines = args.lines or 50
    print(f"## {args.file} (first {lines} lines)\n")

    with open(path) as f:
        for i, line in enumerate(f):
            if i >= lines:
                remaining = sum(1 for _ in f)
                print(f"\n... ({remaining} more lines)")
                break
            print(f"{i+1:4d} | {line}", end="")


def cmd_chunk(args):
    """Split file into chunks for batched processing (RLM: decompose context)."""
    path = PROJECT_ROOT / args.file
    if not path.exists():
        path = Path(args.file)
    if not path.exists():
        print(f"File not found: {args.file}")
        sys.exit(1)

    content = path.read_text()
    chunks = []

    if args.by == "sections":
        sections = extract_sections(content, str(path))
        for section in sections:
            chunks.append({
                'type': 'section',
                'header': section['header'],
                'lines': f"{section['line_start']}-{section['line_end']}",
                'chars': len(section['content']),
                'tokens': len(section['tokens'])
            })
    else:  # lines
        lines = content.split('\n')
        size = args.size or 100
        for i in range(0, len(lines), size):
            chunk_lines = lines[i:i+size]
            chunk_content = '\n'.join(chunk_lines)
            chunks.append({
                'type': 'lines',
                'lines': f"{i+1}-{min(i+size, len(lines))}",
                'chars': len(chunk_content),
                'tokens': len(tokenize(chunk_content))
            })

    print(f"## {args.file} chunked by {args.by}\n")
    print(f"Total chunks: {len(chunks)}")
    print(f"Total chars: {len(content):,}")
    print()

    for i, chunk in enumerate(chunks):
        if chunk['type'] == 'section':
            print(f"  [{i}] {chunk['header'][:50]} (lines {chunk['lines']}, {chunk['tokens']} tokens)")
        else:
            print(f"  [{i}] Lines {chunk['lines']} ({chunk['tokens']} tokens)")


def cmd_topics(args):
    """List all indexed topics/sections for navigation."""
    index = load_index()
    if not index:
        print("No index found. Run: python3 memory.py index")
        sys.exit(1)

    print("## Indexed Topics\n")

    by_file = {}
    for section in index.get('sections', []):
        f = section['file']
        by_file.setdefault(f, []).append(section)

    for f, sections in sorted(by_file.items()):
        print(f"### {f}")
        seen = set()
        for s in sections:
            header = s.get('header', '')
            if header and header not in seen and header != f:
                line_info = f" (L{s.get('line_start', '?')})" if s.get('line_start') else ""
                print(f"  - {header}{line_info}")
                seen.add(header)
        print()


def cmd_stats(args):
    """Show index statistics."""
    index = load_index()
    if not index:
        print("No index found. Run: python3 memory.py index")
        sys.exit(1)

    print("## Index Statistics\n")
    print(f"Created: {index.get('created', 'unknown')}")
    print(f"Root: {index.get('root', 'unknown')}")
    print(f"Files: {len(index.get('files', []))}")
    print(f"Sections: {len(index.get('sections', []))}")
    print(f"Total chars: {index.get('total_chars', 0):,}")
    print(f"Total tokens: {index.get('total_tokens', 0):,}")
    print(f"IDF terms: {len(index.get('idf', {}))}")

    # Top terms by IDF (most distinctive)
    if index.get('idf'):
        print("\n### Most Distinctive Terms (high IDF)")
        sorted_idf = sorted(index['idf'].items(), key=lambda x: -x[1])[:20]
        for term, score in sorted_idf:
            print(f"  {term}: {score:.2f}")


def cmd_batch(args):
    """Search specific files (RLM: targeted sub-queries)."""
    if not args.files:
        print("Error: --files required for batch search")
        sys.exit(1)

    index = load_index()
    if not index:
        print("No index found. Run: python3 memory.py index")
        sys.exit(1)

    full_index = build_index(Path(index['root']) if index.get('root') else None)
    files = [f.strip() for f in args.files.split(',')]
    results = search_index(full_index, args.query, args.top or 10, files)

    print(f"## Batch Search: '{args.query}' in {len(files)} files\n")

    if not results:
        print("No matches found.")
        return

    for i, r in enumerate(results, 1):
        print(f"{i}. {r['file']}:{r['line_start']} [{r['header']}]")
        print(f"   Score: {r['score']:.3f} | {', '.join(r['matched'])}")


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="RLM-inspired memory tool for large documentation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
RLM Concepts (from Recursive Language Models paper):
  - Context as variable: Index docs into searchable environment
  - Programmatic access: peek, chunk, filter operations
  - TF-IDF filtering: Semantic search to narrow search space
  - Batched queries: Search specific file subsets

Examples:
  python3 memory.py index                      # Build index
  python3 memory.py find "authentication"      # Semantic search
  python3 memory.py peek docs/api.md --lines 100
  python3 memory.py chunk docs/spec.md --by sections
  python3 memory.py batch "login" --files docs/auth.md,docs/api.md

For basic file reading, use Claude's native Read tool instead.
        """
    )
    subparsers = parser.add_subparsers(dest="command")

    # index
    index_p = subparsers.add_parser("index", help="Build documentation index")
    index_p.add_argument("--path", help="Custom path to index")

    # find (semantic search)
    find_p = subparsers.add_parser("find", help="TF-IDF semantic search")
    find_p.add_argument("query", help="Search query")
    find_p.add_argument("--top", type=int, default=5, help="Number of results")
    find_p.add_argument("--files", help="Comma-separated file filter")

    # peek
    peek_p = subparsers.add_parser("peek", help="Preview file contents")
    peek_p.add_argument("file", help="File to peek")
    peek_p.add_argument("--lines", type=int, default=50, help="Lines to show")

    # chunk
    chunk_p = subparsers.add_parser("chunk", help="Split file into chunks")
    chunk_p.add_argument("file", help="File to chunk")
    chunk_p.add_argument("--by", choices=["sections", "lines"], default="sections")
    chunk_p.add_argument("--size", type=int, help="Lines per chunk (for --by lines)")

    # topics
    subparsers.add_parser("topics", help="List indexed topics")

    # stats
    subparsers.add_parser("stats", help="Show index statistics")

    # batch
    batch_p = subparsers.add_parser("batch", help="Search specific files")
    batch_p.add_argument("query", help="Search query")
    batch_p.add_argument("--files", required=True, help="Comma-separated files")
    batch_p.add_argument("--top", type=int, default=10, help="Results per file")

    args = parser.parse_args()

    commands = {
        "index": cmd_index,
        "find": cmd_find,
        "peek": cmd_peek,
        "chunk": cmd_chunk,
        "topics": cmd_topics,
        "stats": cmd_stats,
        "batch": cmd_batch,
    }

    if args.command in commands:
        commands[args.command](args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
