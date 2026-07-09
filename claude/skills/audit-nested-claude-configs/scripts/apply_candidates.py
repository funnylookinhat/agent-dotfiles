#!/usr/bin/env python3
"""Promote selected allow-permissions into the global settings.json."""
import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

DEFAULT_GLOBAL = "~/.claude/settings.json"


def backup_global(global_path):
    """Copy the global file into ~/.claude/backups/ with a timestamp; return dest."""
    global_path = Path(global_path).expanduser()
    backups = global_path.parent / "backups"
    backups.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    dest = backups / f"settings.json.{stamp}.bak"
    shutil.copy2(global_path, dest)
    return dest


def merge_allow(settings, entries):
    """Append new entries to permissions.allow; skip exact dupes. Return (settings, added, skipped)."""
    perms = settings.get("permissions")
    if not isinstance(perms, dict):
        perms = {}
        settings["permissions"] = perms
    allow = perms.get("allow")
    if not isinstance(allow, list):
        allow = []
        perms["allow"] = allow
    existing = set(allow)
    added = 0
    skipped = 0
    for entry in entries:
        if entry in existing:
            skipped += 1
            continue
        allow.append(entry)
        existing.add(entry)
        added += 1
    return settings, added, skipped


def apply(global_path, entries):
    """Backup, merge chosen entries into the global allow list, write. Return summary."""
    global_path = Path(global_path).expanduser()
    backup = backup_global(global_path)
    with open(global_path, encoding="utf-8") as fh:
        settings = json.load(fh)
    settings, added, skipped = merge_allow(settings, entries)
    with open(global_path, "w", encoding="utf-8") as fh:
        json.dump(settings, fh, indent=2)
        fh.write("\n")
    return {"added": added, "skipped": skipped, "backup": str(backup)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--global", dest="global_path", default=DEFAULT_GLOBAL)
    parser.add_argument("entries", nargs="+")
    args = parser.parse_args(argv)
    summary = apply(args.global_path, args.entries)
    print(
        f"Added {summary['added']} permission(s), "
        f"skipped {summary['skipped']} duplicate(s)."
    )
    print(f"Backup: {summary['backup']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
