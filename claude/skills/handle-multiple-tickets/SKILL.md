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

## Before the first ticket — resolve the reviewer

Two review skills exist: `/moz-wide:review-pr` (plugin, seomoz repos) and `/reviewing-pr` (personal
fallback). Decide once per run, never per ticket, and never hard-code either name:

```bash
/home/funnylookinhat/.claude/skills/handle-ticket/scripts/resolve-review-skill.sh <owner/repo>
```

Its `.command` is `$REVIEW` below. The answer depends only on the repo owner, so a run whose tickets
span repos resolves once per repo. The same directory holds `review-status.sh <PR>`, which reads
either engine's markers and is the only way you count findings or decide whether a re-review is due.
Call both by absolute path.

## Per-ticket lifecycle

Never start ticket N+1 until step 6 of ticket N is done.

1. **Implement.** `start-worktree` skill, or directly:
   `herdr worktree create --cwd <main repo> --branch <branch> --base <prev branch> --no-focus` →
   `herdr agent start <slug> --kind claude --pane <root-pane-id>` → `herdr agent prompt`. Wait:
   `wait-for-pr.sh <branch> <agent>`.
2. **Review, clean context.** Split a pane in that workspace, start a _fresh_ claude, prompt
   `$REVIEW <PR>`. Wait: `wait-for-agent.sh <agent>`. Then `review-status.sh <PR>`:
   `reviewed == true` and `reviewedSha == headSha` means it ran; `inline` is what it found.
3. **Handle comments, clean context.** Skip when `inline == 0`. Otherwise close that pane, split a
   NEW one, fresh claude, `/handling-pr-comments <PR>`.
4. **Re-review if step 3 committed.** `review-status.sh <PR>` again: `upToDate == false` means the
   head moved past what the review covered — prompt `$REVIEW <PR>` in a fresh pane (both engines go
   incremental on their own) and loop back to 3 if the new review has `inline > 0`. Stop when
   `upToDate == true`, or when the only new commits are docs/comment clarifications asserting
   nothing new, and say so rather than looping.
5. **Verify CI.** `gh pr checks <PR>`. Never report success on a red check.
6. **Finish the worktree.** Split one last pane, fresh claude, `/finish-worktree`.

## Waiting: never poll in your own context

Arm every wait with the **`Monitor` tool, `persistent: true`** — not Bash `run_in_background`
(killed mid-wait in practice). Call this skill's wait scripts by absolute path
(`/home/funnylookinhat/.claude/skills/handle-multiple-tickets/wait-for-*.sh` — they sit at the skill
root, not under `scripts/`); the allow rule
`Bash(/home/funnylookinhat/.claude/skills/handle-multiple-tickets/*)` covers them, and a relative
path misses the glob and prompts. The scripts here emit one line and exit, ending the monitor
cleanly. This is what makes a multi-day run affordable.

**`agent_status` is not a turn-boundary signal.** It stays `working` while background shells the
session spawned keep running, long after the turn ended — so `herdr agent wait --until idle` can
hang forever on a session that is plainly finished. `wait-for-agent.sh` also treats a frozen pane as
SETTLED, which is the case that matters.

**Never act on a wait result alone.** SETTLED is a heuristic (a long silent tool call can trip it
early) and `PR_OPEN` only means the PR exists — a session can open one and keep committing. The
artifact checks (`review-status.sh`, `gh pr view --json commits`, `gh pr checks`) are what actually
gate progress.

**After step 6, `GONE` is the success signal**, not a failure: `/finish-worktree` removes the
workspace, which kills the session you were waiting on. Confirm the real outcome with
`herdr worktree list --cwd <main repo>` (path absent) and `gh pr view <n>` (PR still open, branch
survived).

## Non-obvious mechanics

| Thing                 | What you need to know                                                                                                                                                                                                                                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/finish-worktree`    | Acts on the worktree **its own session** is in; its last step kills that pane. Coordinator cannot invoke it. **Hard-stops on a dirty tree** — check `git status --porcelain` first.                                                                                                                                            |
| Pane reuse            | Don't. Unsubmitted "phantom" text appears at idle prompts and cannot be cleared with `ctrl+u`/`esc`; a new `agent prompt` concatenates onto it. Close the pane, split a new one.                                                                                                                                               |
| Late fixes            | Once finished, the worktree is gone (branch survives, so `--base` still resolves). Land late fixes **before** step 6, or `herdr worktree open` again.                                                                                                                                                                          |
| Fix on a lower branch | Merge that base upward into every branch above it immediately — a **merge**, never a rebase, since they are pushed with open PRs.                                                                                                                                                                                              |
| Review engines        | `/moz-wide:review-pr` posts one PR _review_ with `<!-- moz-review:v1 sha=… -->`; `/reviewing-pr` posts an issue comment with `<!-- reviewing-pr:sha=… -->`. `review-status.sh` reads both. The plugin declines repos outside seomoz and drafts by other authors; the resolver already routes non-seomoz repos to the fallback. |
| Test flakiness        | Each worktree has its **own** compose project and DB container — they are not shared. A killed test run leaves an orphaned mocha process inside _that_ worktree's container: `docker exec <app> ps aux \| grep mocha`.                                                                                                         |

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
