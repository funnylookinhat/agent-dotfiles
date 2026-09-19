---
name: handle-ticket
description:
  Use when asked to take one Jira ticket from its ID through to an open, reviewed pull request,
  hands-off, in its own isolated worktree. For two or more tickets use handle-multiple-tickets
  instead. Requires HERDR_ENV=1.
---

# Handle Ticket

One ticket, one worktree, one coordinator that never writes code. The work runs in a **new Herdr
workspace**: its root pane holds the coordinator, and a single pane to its right is created, used,
and closed once per phase.

```
your pane            new workspace
(launcher)    ──►    ┌────────────┬────────────┐
 hands off,          │ COORDINATOR│ one worker │
 then done           │ (root pane)│ at a time  │
                     └────────────┴────────────┘
```

## Which role am I?

**Invoked with `--coordinate`** → you are the coordinator. Skip to [Role 2](#role-2--coordinate).
**Anything else** → you are the launcher. Start at [Role 1](#role-1--launch).

## Preconditions (both roles)

- `test "${HERDR_ENV:-}" = 1` — if not, say you are not inside Herdr and stop.
- `git -C "$PWD" rev-parse --show-toplevel` succeeds.

---

## Role 1 — Launch

Your whole job is to build the brief and hand off. **You do not drive the lifecycle and you do not
wait for it.** When step 6 returns, you are finished.

1. **Find the ticket ID** in the arguments — `[A-Z][A-Z0-9]+-[0-9]+`. No match → ask for one and
   stop. Keep any other text on the invocation line; it becomes _Extra instructions_ in the brief.

2. **Fetch the ticket.** `mcp__atlassian__getAccessibleAtlassianResources` for the `cloudId`, then
   `mcp__atlassian__getJiraIssue`.

3. **Write the brief** with the Write tool to `~/.claude/ticket-runs/<TICKET>/brief.md`: ticket key
   and URL, summary, full description, acceptance criteria, and _Extra instructions_. Put it
   **outside the repo** — the worktree must stay clean, and a dirty tree blocks teardown later. Copy
   the description verbatim; do not summarize it.

4. **Create the worktree.** Branch `flh/<TICKET>-<kebab-summary>` (base = default branch unless the
   user named one):

   ```bash
   herdr worktree create --cwd "$PWD" --branch flh/<TICKET>-<slug> --no-focus
   ```

   Capture `.result.root_pane.pane_id`, `.result.workspace.workspace_id`, and
   `.result.worktree.path` from the JSON. Never guess an ID.

5. **Start the coordinator in the root pane** — the root pane is already an available shell; do not
   split it. `<t>` is the ticket lowercased with no punctuation (`APDEV-6200` → `apdev6200`); it
   prefixes every agent name in this run:

   ```bash
   herdr agent start <t>-coord --kind claude --pane <root-pane-id>
   ```

6. **Hand off, fire-and-forget** — no `--wait`:

   ```bash
   herdr agent prompt <t>-coord '/handle-ticket --coordinate <TICKET> brief=<abs-brief-path> branch=flh/<TICKET>-<slug> worktree=<path> pane=<root-pane-id> workspace=<workspace-id>'
   ```

   Expand `~` yourself — every path in that prompt must be **absolute**. It arrives as text in
   another agent's prompt box, where no shell expands it and a `~` path is not readable.

7. **Report** branch, worktree path, workspace ID, coordinator agent name, and that results will
   arrive as a Herdr notification plus `~/.claude/ticket-runs/<TICKET>/report.md`. Then stop.

---

## Role 2 — Coordinate

You are in the worktree's root pane. **You never write the ticket's code** — every phase runs in a
worker session in the pane to your right. Read the brief first, and confirm
`git rev-parse --show-toplevel` matches the `worktree=` you were given.

Keep running notes in `~/.claude/ticket-runs/<TICKET>/notes.md` as phases complete.

### The phase cycle

Every phase is the same four moves. **Split, start, wait, close** — the close is what keeps the
layout usable and guarantees the next context is clean:

```bash
herdr pane split --pane <root-pane-id> --direction right --cwd <worktree> --no-focus
herdr agent start <name> --kind claude --pane <new-pane-id>
herdr agent prompt <name> '<prompt>'          # no --wait, ever
# ... wait (see below) ...
herdr pane close <new-pane-id>
```

There is **never more than one worker pane alive.** Close the previous one before splitting the
next.

### Phases

Call the wait scripts by **absolute path** — your cwd is the worktree, so a relative `scripts/…`
resolves to a file that does not exist, and it would miss the allowlist glob and prompt. Write `$W`
below in full:

```
$W = /home/funnylookinhat/.claude/skills/handle-ticket/scripts
```

1. **Implement** — agent `<t>-impl`. Prompt: the brief's full text, plus "follow this repo's
   CLAUDE.md for tests/lint/build, commit with conventional commits, push, and open a PR with
   `gh pr create`." Wait on: `$W/wait-for-pr.sh <branch> <t>-impl`.

2. **Review** — agent `<t>-review`, prompt `/reviewing-pr <PR>`. Wait on:
   `$W/wait-for-agent.sh <t>-review`.

3. **Handle comments** — agent `<t>-comments`, prompt `/handling-pr-comments <PR>`. Wait on:
   `$W/wait-for-agent.sh <t>-comments`. **Skip this phase entirely if phase 2 posted zero inline
   findings** — go straight to phase 5. Spinning up a session to handle nothing costs minutes and a
   pane.

4. **Re-review if phase 3 committed.** Check `gh pr view <PR> --json commits`. New commits mean the
   phase-2 review covered a tree that no longer exists — run `/reviewing-pr <PR>` again (it goes
   incremental on its own) as `<t>-review2`, and loop back to 3 if it posts anything. **Stop
   looping** when `/reviewing-pr` reports `mode == "none"`, or when the only new commits are
   docs/comment clarifications that assert nothing new — say so rather than looping again.

5. **Check CI.** `gh pr checks <PR>`. **Never report success on a red check.** Red → report it as
   red; do not start another fix phase unless the user asked for one.

6. **Report and stop.** Write `~/.claude/ticket-runs/<TICKET>/report.md` (PR URL, what each phase
   did, CI state, anything escalated), then:
   ```bash
   herdr notification show '<TICKET> ready' --body 'PR #<n> reviewed; CI <state>' --sound done
   ```
   **Leave the worktree up.** Do not run `/finish-worktree`, `herdr worktree remove`, or close your
   own pane — the user tears it down when they are ready.

### Waiting: never block your own context

Arm every wait with the **Monitor tool** on the bundled script. The scripts emit exactly one line
and exit, which ends the monitor cleanly.

Monitor's deadline caps at **1800000 ms**, and a phase can outlast it. On an expiry with no event,
**re-arm the same command** — the script is a fresh poll loop each time, so re-arming loses nothing.
Keep re-arming until it emits a line.

| Do                                                                          | Don't                                                                |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `Monitor` on `$W/wait-for-pr.sh` / `$W/wait-for-agent.sh`, by absolute path | `herdr agent prompt … --wait` — blocks your turn for the whole phase |
| Re-arm on Monitor expiry                                                    | Treat an expiry with no event as "it finished"                       |
| `herdr agent get` once, after the wait fires                                | Poll `agent get` in a loop in your own context                       |

**`agent_status` is not a turn boundary.** It stays `working` while background shells the session
spawned keep running, so `herdr agent wait --until idle` can hang forever on a session that is
plainly finished. `wait-for-agent.sh` exists because of this: it treats a frozen pane as `SETTLED`,
which is the case that matters.

**Never act on a wait result alone.** `SETTLED` is a heuristic — a long silent tool call can trip it
early — and `PR_OPEN` only means the PR exists; the session may still be committing. Confirm with
the artifact before moving on.

### What each wait outcome means

The scripts emit one line and exit. Every outcome needs an action — **a wait that ends is not the
same as a phase that succeeded**:

| Line                       | Meaning                        | Do                                                                                                                                                                                                                                     |
| -------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PR_OPEN <branch> #<n>`    | the PR exists                  | Verify commits, then advance.                                                                                                                                                                                                          |
| `DONE` / `SETTLED <agent>` | the turn is over               | Verify the phase's artifact, then advance.                                                                                                                                                                                             |
| `BLOCKED <agent>`          | the worker is waiting on input | `herdr agent read <agent> --source recent-unwrapped --lines 120`. Answer it with `herdr agent prompt` only if the brief already settles the question; otherwise escalate — do not invent requirements or approve on the user's behalf. |
| `STALLED <agent>`          | idle ~15 min, no PR            | Read the pane. It is stuck or waiting silently. One nudge prompt is fair; a second `STALLED` means escalate.                                                                                                                           |
| `GONE <agent>`             | not resolvable                 | The session or pane died. **Never treat this as success** — this skill never removes a worktree, so nothing should legitimately vanish. Report it.                                                                                     |

Escalating means: write what happened to `report.md`, fire the notification, and stop. Leave the
worktree and the PR exactly as they are for the user to inspect.

### Verify, don't trust

Worker sessions have claimed commits that did not exist. Before each phase transition:

- Phase 1 → 2: `gh pr view <PR> --json commits,baseRefName` — commits are real, base is what you
  intended.
- Phase 2 → 3: two different questions, two different endpoints — **did the review run?** (issue
  comments carry the sha marker; one always posts, even with zero findings):
  `gh api repos/<owner>/<repo>/issues/<PR>/comments --jq '[.[] | select(.body | contains("reviewing-pr:sha="))] | length'`
  ≥ 1. **did it find anything?** (inline review comments — this is the count the phase-3 skip keys
  on; zero here means skip):
  `gh api repos/<owner>/<repo>/pulls/<PR>/comments --jq '[.[] | select(.body | startswith("SKILL:Reviewing-PR"))] | length'`.
- Phase 3 → 4: `gh pr view <PR> --json commits` — did it commit, or only reply?

### Escalate, never fake

Some gates only a human can clear: PR-template checkboxes attesting to manual smoke tests,
`terraform plan` needing SSO, hook-blocked operations. Collect them into `report.md` and the
notification. **Never tick an attestation checkbox** — it claims testing nobody performed.

---

## Non-obvious mechanics

| Thing              | What you need to know                                                                                                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Freeing a pane     | There is no `herdr agent stop`. `herdr pane close <id>` is how a phase ends; split a new pane for the next one.                                                                       |
| Pane reuse         | Don't. Unsubmitted "phantom" text survives at an idle prompt, cannot be cleared with `ctrl+u`/`esc`, and the next `agent prompt` concatenates onto it.                                |
| Repeated splits    | Always split from the **root pane**, never from the previous worker pane — chaining rightward produces unusably narrow columns.                                                       |
| Agent names        | `[a-z][a-z0-9_-]{0,31}`, unique among _live_ agents. Closing a pane frees the name; on `name already in use`, append a digit.                                                         |
| Coordinator cwd    | The worktree, so `gh` resolves the repo and the wait scripts work with no `GH_REPO`.                                                                                                  |
| Docker             | Each worktree gets its own compose project and containers — not shared with your main checkout. A killed test run can leave an orphaned mocha process in _that_ worktree's container. |
| `/finish-worktree` | Acts on the worktree its own session is in and kills that pane. Out of scope here; this skill always leaves the worktree up.                                                          |

## Running unattended

The coordinator must never hit a permission prompt — a prompt mid-run stalls it silently until
someone looks. Beyond the rules `reviewing-pr` and `handling-pr-comments` already rely on, this
skill needs:

```jsonc
// ~/.claude/settings.json → permissions.allow
"Bash(/home/funnylookinhat/.claude/skills/handle-ticket/scripts/*)",
```

Run each `herdr`, `git`, and `gh` command as its own Bash call — a compound line (`cd … && …`,
`a; b`) is matched as one blob and prompts no allowlist entry can cover.

## Common mistakes

- **Coordinating from the launcher session.** The launcher's job ends at the handoff; the
  coordinator lives in the new workspace's root pane. If you find yourself waiting on a worker from
  the main checkout, you skipped the handoff.
- **`agent prompt --wait`.** It looks like the simple way to sequence phases and costs you the
  entire phase's wall-clock inside one turn. Use Monitor.
- **Leaving worker panes open.** Four panes across a workspace are unreadable, and the next phase's
  "clean context" is only clean because the previous pane is gone.
- **Reporting done without `gh pr checks`.** A green-looking review says nothing about CI.
- **Stopping after phase 3.** Handling comments changes the code the review was about; phase 4
  exists for that and terminates on `mode == "none"`.
- **Writing the brief into the worktree.** It dirties the tree and later blocks teardown.
- **Running `/finish-worktree`.** Out of scope — the run ends with the worktree up.
