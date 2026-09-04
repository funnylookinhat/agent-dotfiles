---
name: handle-multiple-tickets
description:
  Use when asked to work through two or more tickets end-to-end in sequence, each in its own Herdr
  worktree with its own Claude session, taking each to an open reviewed PR before starting the next.
  Requires HERDR_ENV=1.
---

# Handle Multiple Tickets

Run N tickets through an identical lifecycle, one at a time, each in its own worktree. You are the
coordinator: you dispatch sessions, wait out-of-context, verify claims, carry findings forward, and
report. **You never write the code yourself.**

Each ticket's branch is based on the previous ticket's branch (a stack) unless the user says they
are independent.

## Per-ticket lifecycle

Never start ticket N+1 until step 6 of ticket N is done.

1. **Implement.** `start-worktree` skill, or directly:
   `herdr worktree create --cwd <main repo> --branch <branch> --base <prev branch> --no-focus` →
   `herdr agent start <slug> --kind claude --pane <root-pane-id>` → `herdr agent prompt`. Wait:
   `wait-for-pr.sh <branch> <agent>`.
2. **Review, clean context.** Split a pane in that workspace, start a _fresh_ claude, prompt
   `/reviewing-pr <PR>`. Wait: `wait-for-agent.sh <agent>`.
3. **Handle comments, clean context.** Close that pane, split a NEW one, fresh claude,
   `/handling-pr-comments <PR>`.
4. **Re-review if step 3 committed.** The step-2 review covered a tree that no longer exists;
   `/reviewing-pr` does an incremental pass. Loop back to 3 if it finds anything. Stop when the only
   new commits are docs/comment clarifications asserting nothing new, and say so rather than
   looping.
5. **Verify CI.** `gh pr checks <PR>`. Never report success on a red check.
6. **Finish the worktree.** Split one last pane, fresh claude, `/finish-worktree`.

## Waiting: never poll in your own context

Arm every wait with the **`Monitor` tool, `persistent: true`** — not Bash `run_in_background`
(killed mid-wait in practice). The scripts here emit one line and exit, ending the monitor cleanly.
This is what makes a multi-day run affordable.

**`agent_status` is not a turn-boundary signal.** It stays `working` while background shells the
session spawned keep running, long after the turn ended — so `herdr agent wait --until idle` can
hang forever on a session that is plainly finished. `wait-for-agent.sh` also treats a frozen pane as
SETTLED, which is the case that matters.

**Never act on a wait result alone.** SETTLED is a heuristic (a long silent tool call can trip it
early) and `PR_OPEN` only means the PR exists — a session can open one and keep committing. The
artifact check in step 5 is what actually gates progress.

**After step 6, `GONE` is the success signal**, not a failure: `/finish-worktree` removes the
workspace, which kills the session you were waiting on. Confirm the real outcome with
`herdr worktree list --cwd <main repo>` (path absent) and `gh pr view <n>` (PR still open, branch
survived).

## Non-obvious mechanics

| Thing                 | What you need to know                                                                                                                                                                                                  |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/finish-worktree`    | Acts on the worktree **its own session** is in; its last step kills that pane. Coordinator cannot invoke it. **Hard-stops on a dirty tree** — check `git status --porcelain` first.                                    |
| Pane reuse            | Don't. Unsubmitted "phantom" text appears at idle prompts and cannot be cleared with `ctrl+u`/`esc`; a new `agent prompt` concatenates onto it. Close the pane, split a new one.                                       |
| Late fixes            | Once finished, the worktree is gone (branch survives, so `--base` still resolves). Land late fixes **before** step 6, or `herdr worktree open` again.                                                                  |
| Fix on a lower branch | Merge that base upward into every branch above it immediately — a **merge**, never a rebase, since they are pushed with open PRs.                                                                                      |
| Test flakiness        | Each worktree has its **own** compose project and DB container — they are not shared. A killed test run leaves an orphaned mocha process inside _that_ worktree's container: `docker exec <app> ps aux \| grep mocha`. |

## Carry findings forward

Reviews surface issues belonging to a **later** ticket. Keep a running notes file and inject the
relevant items verbatim into each later launch prompt — assign each to the ticket that first makes
it reachable, which is often not the obvious one.

## Verify, don't trust

Agent reports have claimed commits that did not exist. Confirm with `gh pr view <n> --json commits`
or `git -C <worktree> log`. Also confirm `baseRefName` is the intended base, and that the
implementing session is genuinely idle before reviewing.

## Escalate, never fake

Some gates only a human can clear: PR-template checkboxes attesting to manual smoke tests,
`terraform plan` needing SSO, hook-blocked stash drops. Collect them and report them. **Never tick
an attestation checkbox** — it claims testing nobody performed.
