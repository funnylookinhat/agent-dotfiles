#!/usr/bin/env python3
"""Gather promotable allow-permissions from nested .claude config files."""
import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_ROOT = "/home/funnylookinhat/source/"
DEFAULT_GLOBAL = "~/.claude/settings.json"

_ENTRY_RE = re.compile(r"^([A-Za-z_]+)\((.*)\)$")


def _tool_and_arg(entry):
    """'Bash(git rm:*)' -> ('Bash', 'git rm:*'); 'mcp__x' -> ('mcp__x', None)."""
    m = _ENTRY_RE.match(entry)
    if m:
        return m.group(1), m.group(2)
    return entry, None


def _coverage_prefix(arg):
    """Reduce an arg to its coverage prefix: cut at first '*', strip trailing ':'/space."""
    star = arg.find("*")
    a = arg[:star] if star != -1 else arg
    return a.rstrip(": ")


def _prefix_covers(global_prefix, cand_prefix):
    """True if cand_prefix falls under global_prefix at a path/word boundary."""
    g = global_prefix.replace(":", " ")
    c = cand_prefix.replace(":", " ")
    if g == "":
        return True
    if c == g:
        return True
    if not c.startswith(g):
        return False
    if g[-1] in (" ", "/"):
        return True
    return c[len(g):len(g) + 1] in (" ", "/")


def covers(global_entry, candidate):
    """True if the global entry already subsumes the candidate."""
    gt, ga = _tool_and_arg(global_entry)
    ct, ca = _tool_and_arg(candidate)
    if ga is None and ca is None:
        # Bare tokens: WebFetch, mcp__server, mcp__server__method.
        return candidate == global_entry or candidate.startswith(global_entry + "__")
    if gt != ct:
        return False
    if ga is None:
        # Global is a bare tool name (e.g. "Bash"): covers all of that tool.
        return True
    if ca is None:
        return False
    return _prefix_covers(_coverage_prefix(ga), _coverage_prefix(ca))


def is_covered(candidate, global_allow):
    """True if any global allow-entry subsumes the candidate."""
    return any(covers(g, candidate) for g in global_allow)


def find_config_files(root):
    """All .claude/settings.json and .claude/settings.local.json under root."""
    root = Path(root)
    names = ("settings.json", "settings.local.json")
    files = []
    for claude_dir in root.rglob(".claude"):
        if not claude_dir.is_dir():
            continue
        for name in names:
            candidate = claude_dir / name
            if candidate.is_file():
                files.append(candidate)
    return sorted(files)


def project_name(config_path):
    """Basename of the directory containing the .claude dir."""
    return Path(config_path).parent.parent.name


def _read_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def load_allow(config_path):
    """permissions.allow (string entries only) from a config file; [] if absent/wrong-typed."""
    perms = _read_json(config_path).get("permissions", {}) or {}
    if not isinstance(perms, dict):
        return []
    allow = perms.get("allow", []) or []
    if not isinstance(allow, list):
        return []
    return [a for a in allow if isinstance(a, str)]


def count_deny_ask(config_path):
    """len(permissions.deny) + len(permissions.ask); 0 for absent/wrong-typed."""
    perms = _read_json(config_path).get("permissions", {}) or {}
    if not isinstance(perms, dict):
        return 0
    deny = perms.get("deny", []) or []
    ask = perms.get("ask", []) or []
    deny_n = len(deny) if isinstance(deny, list) else 0
    ask_n = len(ask) if isinstance(ask, list) else 0
    return deny_n + ask_n


def load_global_allow(global_path):
    """permissions.allow (string entries only) from the global settings file; [] if unreadable."""
    try:
        perms = _read_json(Path(global_path).expanduser()).get("permissions", {}) or {}
    except (OSError, json.JSONDecodeError, TypeError, AttributeError):
        return []
    if not isinstance(perms, dict):
        return []
    allow = perms.get("allow", []) or []
    if not isinstance(allow, list):
        return []
    return [a for a in allow if isinstance(a, str)]


def gather(root, global_path):
    """Collect promotable candidates with provenance, excluding covered entries."""
    global_allow = load_global_allow(global_path)
    candidates = {}
    skipped_deny_ask = 0
    files_scanned = 0
    files_failed = []
    for path in find_config_files(root):
        try:
            allow = load_allow(path)
            skipped_deny_ask += count_deny_ask(path)
        except (OSError, json.JSONDecodeError, TypeError, AttributeError):
            files_failed.append(str(path))
            continue
        files_scanned += 1
        proj = project_name(path)
        for entry in allow:
            if is_covered(entry, global_allow):
                continue
            candidates.setdefault(entry, set()).add(proj)
    return {
        "candidates": {e: sorted(p) for e, p in sorted(candidates.items())},
        "skipped_deny_ask": skipped_deny_ask,
        "files_scanned": files_scanned,
        "files_failed": files_failed,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=DEFAULT_ROOT)
    parser.add_argument("--global", dest="global_path", default=DEFAULT_GLOBAL)
    args = parser.parse_args(argv)
    result = gather(Path(args.root).expanduser(), args.global_path)
    for failed in result["files_failed"]:
        print(f"warning: could not parse {failed}", file=sys.stderr)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
