---
name: handoff-to-worktree
description:
  Use when the user invokes /handoff-to-worktree with instructions, or asks to hand the current
  session's work off to a fresh Claude session in a new git worktree — e.g. they're leaving, the
  session is long, or the remaining work should continue elsewhere. Requires a Herdr-managed pane
  (HERDR_ENV=1) and a git repository.
---

# Handoff To Worktree

Package this session's context into a handoff document, then start a Claude session in a new
worktree that works from that document. The document is the handoff — the prompt just points at it.

**Arguments:** everything after the invocation is the instruction for the new session (goes in the
doc verbatim and in the prompt). If empty, ask what the new session should do.

**REQUIRED SUB-SKILL:** use `start-worktree` for the mechanics — preconditions, branch/agent naming,
`herdr worktree create`, `herdr agent start`. Only the steps below differ.

## Recipe

1. **Create the worktree first** (per start-worktree, steps 1–2: naming, `worktree create`). You
   need the checkout path before you can write the handoff file.

2. **Write `HANDOFF.md` at the checkout root**, then keep it out of git:

   ```bash
   ex=$(git -C <checkout> rev-parse --git-path info/exclude)
   grep -qx 'HANDOFF.md' "$ex" || echo 'HANDOFF.md' >> "$ex"
   ```

3. **Start claude and prompt it** (per start-worktree steps 3–4, fire-and-forget):

   ```
   Read HANDOFF.md in the repo root, then: <instructions verbatim>
   ```

4. **Report back** per start-worktree step 5, plus the handoff file path.

## HANDOFF.md contract

Written for a reader with zero access to this conversation: every file by path, every decision with
its reason. Sections, in order:

```markdown
# Handoff: <one-line goal>

## Instructions

<the user's instructions, verbatim>

## Work items

- [ ] <concrete task, one per line, in execution order>

## Context

<decisions already made and why; constraints (e.g. "no new dependencies"); explicit do-not-touch
items and why; relevant files by path; known-good commands (tests, build, run)>

## Already done

<what this session completed, so nothing is redone>
```

Work items come from the session's actual remaining work — reread the conversation for agreed
approaches, user vetoes, and half-finished threads; those become Context and Work items, not just
the final request.

## Common mistakes

- Inlining the whole context into `agent prompt` — long CLI args are fragile, and the new session
  can't re-read a prompt after compaction. The file is the handoff.
- Writing HANDOFF.md before the worktree exists, in the source repo — it belongs in the new
  checkout, which `worktree create` returns.
- Summarizing what happened chronologically instead of what remains — the new session needs work
  items and constraints, not a session diary.
- Omitting user vetoes ("don't touch X", "no new libraries") — the new session will happily redo
  rejected approaches.
