---
name: audit-nested-claude-configs
description:
  Use when you want to find Claude Code permissions scattered across per-project
  .claude/settings.json and settings.local.json files under ~/source/ and decide which generic ones
  to promote into the global ~/.claude/settings.json.
---

# Audit Nested Claude Configs

Recommend `allow` permissions from nested project `.claude` configs that are worth promoting to the
global `~/.claude/settings.json`, then apply the ones the user picks.

## Steps

1. **Gather candidates.** Run the gather script (add `--root DIR` only if the user named a different
   tree):

   ```bash
   python3 ~/.claude/skills/audit-nested-claude-configs/scripts/gather_candidates.py
   ```

   It prints JSON: `candidates` (map of allow-entry → source project names), `skipped_deny_ask`,
   `files_scanned`, `files_failed`. Entries the global config already covers are already excluded.

2. **Handle the empty case.** If `candidates` is empty, tell the user there is nothing to promote,
   report `files_scanned` and any `files_failed`, and stop.

3. **Judge each candidate — keep only generic, reusable permissions.** Exclude a candidate when it
   is project-specific:
   - It contains an absolute path (`/home/`, a leading `/`) or a specific repo name.
   - It names a specific filename, line, or commit message.
   - It is a one-off inline script: `python3 -c "..."`, `awk ...`, `xargs -I{} sh -c ...`, or a
     `grep`/command with concrete literals instead of a `*` wildcard.

   Keep clean wildcard patterns (`Bash(npm list *)`), whole-command grants (`Bash(git rm *)`), and
   MCP method grants (`mcp__atlassian__getJiraIssue`). When genuinely unsure, keep it and mark it
   `(review)`.

4. **Present a checklist**, grouped by tool — `Bash`, `Read`/`Write`/`Edit`, `mcp__*`, `Skill`, then
   everything else. Show each entry with its source projects. Add a footnote with the
   `skipped_deny_ask` count and any `files_failed`.

5. **Ask which to apply** — all, none, or a subset.

6. **Apply.** For the chosen entries, run the apply script, passing each entry as a separate quoted
   argument:

   ```bash
   python3 ~/.claude/skills/audit-nested-claude-configs/scripts/apply_candidates.py \
     'Bash(npm list *)' 'mcp__atlassian__getJiraIssue'
   ```

   Relay its summary: how many were added, how many skipped as duplicates, and the backup path.
   Never edit the nested project configs — they are read-only here.
