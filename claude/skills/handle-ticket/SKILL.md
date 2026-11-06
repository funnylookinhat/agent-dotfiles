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

## Preconditions

- Both roles: `test "${HERDR_ENV:-}" = 1` — if not, say you are not inside Herdr and stop.
- Coordinator only: `git rev-parse --show-toplevel` equals the `worktree=` you were given.

The launcher has **no** working-directory precondition. It can run from anywhere — the repository
comes from the ticket, not from `$PWD` (Role 1, step 4).

---

## Role 1 — Launch

Your whole job is to build the brief and hand off. **You do not drive the lifecycle and you do not
wait for it.** When step 7 returns, you are finished.

1. **Find the ticket ID** in the arguments — `[A-Z][A-Z0-9]+-[0-9]+`. No match → ask for one and
   stop. Keep any other text on the invocation line; it becomes _Extra instructions_ in the brief. A
   `base=<ref>` token, or an explicit instruction such as "branch off `release/2.x`", is a **base
   override** — note it for step 4. Nothing else is: the branch currently checked out, and branches
   the ticket merely mentions as context, are not instructions.

2. **Fetch the ticket.** `mcp__atlassian__getAccessibleAtlassianResources` for the `cloudId`, then
   `mcp__atlassian__getJiraIssue`.

3. **Write the brief** with the Write tool to `~/.claude/ticket-runs/<TICKET>/brief.md`: ticket key
   and URL, summary, full description, acceptance criteria, and _Extra instructions_. Put it
   **outside the repo** — the worktree must stay clean, and a dirty tree blocks teardown later. Copy
   the description verbatim; do not summarize it — the next step parses the description's
   `Repository` section out of this file.

4. **Resolve the repository.** The ticket's `## Repository` section names the GitHub `OWNER/REPO`;
   checkouts live at `~/source/github.com/<owner>/<repo>`. Never assume `$PWD` is the repo — you may
   have been launched from anywhere.

   ```bash
   /home/funnylookinhat/.claude/skills/handle-ticket/scripts/resolve-ticket-repo.sh <abs-brief-path> --cwd "$PWD"
   ```

   Read `.status`, `.repo`, and `.path` from the JSON. `$REPO_PATH` below is `.path`, and `.repo` is
   the `OWNER/REPO` the coordinator will need.

   | `.status`                   | Do                                                                                                                                                                                                                    |
   | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `OK`, `.source == "ticket"` | Proceed.                                                                                                                                                                                                              |
   | `OK`, `.source == "cwd"`    | The ticket names no repository and you happen to be inside a checkout. Say which repo you are defaulting to in the report; if the user named a different one on the invocation line, re-run with `--repo OWNER/REPO`. |
   | `NOT_FOUND`                 | No section, not inside a checkout. Ask the user for `OWNER/REPO` and stop. Do not guess from the ticket's prose.                                                                                                      |
   | `NOT_CLONED`                | The ticket names a repo with no checkout here. Report the clone command from `.reason` and stop — cloning is the user's call.                                                                                         |
   | `NONE`                      | The ticket says it changes no code. There is nothing to implement in a worktree; report that and stop.                                                                                                                |

   **Then resolve the base.** The new branch starts from the repository's **default branch, freshly
   fetched from origin** — never from whatever the checkout happens to have checked out. Pass
   `--base <ref>` only when step 1 found a base override; the ticket's own `## Base branch` section,
   if it has one, counts as an override too.

   ```bash
   /home/funnylookinhat/.claude/skills/handle-ticket/scripts/resolve-base-branch.sh --cwd "$REPO_PATH" [--base <ref>]
   ```

   It fetches the branch from origin, fast-forwards the local branch when that is safe, and prints
   JSON. `$BASE` below is `.base` **verbatim** (a branch name, or a commit when the local branch
   could not be brought in sync), and `.branch` is the base's name for the PR.

   | `.status`                  | Do                                                                                                                                                        |
   | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `OK`                       | Proceed. Mention in the report when `.localFastForwarded` is true or `.localInSync` is false (the local branch was dirty or diverged and was left alone). |
   | `FETCH_FAILED`             | Origin is unreachable. Do not fall back to the local branch — report `.reason` and stop; a stale base silently produces a PR with the wrong diff.         |
   | `NOT_FOUND`                | The override names a branch that exists nowhere. Report it and stop.                                                                                      |
   | `NO_DEFAULT` / `NO_ORIGIN` | Report `.reason` and stop.                                                                                                                                |

5. **Create the worktree.** Branch `flh/<TICKET>-<kebab-summary>`, **always** with `--base` —
   without it Herdr starts the branch from the checkout's current `HEAD`:

   ```bash
   herdr worktree create --cwd "$REPO_PATH" --branch flh/<TICKET>-<slug> --base "$BASE" --no-focus
   ```

   Capture `.result.root_pane.pane_id`, `.result.workspace.workspace_id`, and
   `.result.worktree.path` from the JSON. Never guess an ID.

6. **Start the coordinator in the root pane** — the root pane is already an available shell; do not
   split it. `<t>` is the ticket lowercased with no punctuation (`APDEV-6200` → `apdev6200`); it
   prefixes every agent name in this run:

   ```bash
   herdr agent start <t>-coord --kind claude --pane <root-pane-id>
   ```

7. **Hand off, fire-and-forget** — no `--wait`:

   ```bash
   herdr agent prompt <t>-coord '/handle-ticket --coordinate <TICKET> brief=<abs-brief-path> repo=<OWNER/REPO> branch=flh/<TICKET>-<slug> base=<.branch from step 4> worktree=<path> pane=<root-pane-id> workspace=<workspace-id>'
   ```

   Expand `~` yourself — every path in that prompt must be **absolute**. It arrives as text in
   another agent's prompt box, where no shell expands it and a `~` path is not readable.

8. **Report** repository (and whether it came from the ticket or from `$PWD`), branch, base (and
   whether it was the default or an override, and whether the local branch was fast-forwarded or
   left alone), worktree path, workspace ID, coordinator agent name, and that results will arrive as
   a Herdr notification plus `~/.claude/ticket-runs/<TICKET>/report.md`. Then stop.

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

**Before phase 1 — resolve the reviewer.** Two review skills exist: `/moz-wide:review-pr` (the
plugin skill, for repos in the seomoz org) and `/reviewing-pr` (the personal fallback). Decide once
per run, using the `repo=` you were handed, and write the answer to `notes.md`:

```bash
$W/resolve-review-skill.sh <repo=OWNER/REPO>
```

Its `.command` is `$REVIEW` in every phase below. Never hard-code either name: a worker prompted
with a skill its session does not have asks what you meant, and the wait reports `BLOCKED`.

1. **Implement** — agent `<t>-impl`. Prompt: the brief's full text, plus "follow this repo's
   CLAUDE.md for tests/lint/build, commit with conventional commits, push, and open a PR with
   `gh pr create --base <base>`" — `<base>` is the `base=` you were handed, so a run based on a
   release branch does not open its PR against the default branch. Wait on:
   `$W/wait-for-pr.sh <branch> <t>-impl`.

2. **Review** — agent `<t>-review`, prompt `$REVIEW <PR>` (e.g.
   `/moz-wide:review-pr https://github.com/seomoz/<repo>/pull/<n>`). Wait on:
   `$W/wait-for-agent.sh <t>-review`.

3. **Handle comments** — agent `<t>-comments`, prompt `/handling-pr-comments <PR>`. Wait on:
   `$W/wait-for-agent.sh <t>-comments`. **Skip this phase entirely if `review-status.sh` reports
   `inline == 0`** — go straight to phase 5. Spinning up a session to handle nothing costs minutes
   and a pane. Any inline finding counts, `[pre-existing]` ones included — the handling skill
   decides per thread.

4. **Re-review if phase 3 committed.** Run `$W/review-status.sh <PR>`. `upToDate == false` means the
   head moved past the sha the review covered — run `$REVIEW <PR>` again as `<t>-review2` (both
   engines re-review incrementally on their own), then re-run `review-status.sh` and loop back to 3
   if the new review has `inline > 0`. **Stop looping** when `upToDate == true` (replies alone never
   move the head, so a phase 3 that only replied ends here), or when the only new commits are
   docs/comment clarifications that assert nothing new — say so rather than looping again.

5. **Check CI.** `gh pr checks <PR>`. **Never report success on a red check.** Red → report it as
   red; do not start another fix phase unless the user asked for one.

6. **Free the machine.** Everything the workers started is still resident — compose containers, dev
   servers, watchers, an orphaned test runner — and the worktree stays up, so nothing else will ever
   stop them:

   ```bash
   $W/stop-worktree-services.sh <worktree>
   ```

   It downs the worktree's compose project(s), kills stray processes whose cwd is the worktree, and
   leaves shells and claude alone; its JSON says exactly what it did. Paste the `compose` and
   `processes` arrays into the report. Run it whenever you are about to fire the notification with
   **no worker pane alive** — a worker parked at a question (a `BLOCKED` escalation) still needs its
   containers, so in that one case leave them up and say so in the report.

7. **Report and stop.** Write `~/.claude/ticket-runs/<TICKET>/report.md` (PR URL, what each phase
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

| Line                       | Meaning                        | Do                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `PR_OPEN <branch> #<n>`    | the PR exists                  | Verify commits, then advance.                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `DONE` / `SETTLED <agent>` | the turn is over               | Verify the phase's artifact, then advance.                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `BLOCKED <agent>`          | the worker is waiting on input | `herdr agent read <agent> --source recent-unwrapped --lines 120`. Answer it with `herdr agent prompt` only if the brief already settles the question; otherwise escalate — do not invent requirements or approve on the user's behalf. `/moz-wide:review-pr` stops and asks when it cannot state the PR's purpose from the PR, branch, ticket, and linked docs — the brief's summary and acceptance criteria usually answer that, and the review records them as `invoker-supplied`. |
| `STALLED <agent>`          | idle ~15 min, no PR            | Read the pane. It is stuck or waiting silently. One nudge prompt is fair; a second `STALLED` means escalate.                                                                                                                                                                                                                                                                                                                                                                         |
| `GONE <agent>`             | not resolvable                 | The session or pane died. **Never treat this as success** — this skill never removes a worktree, so nothing should legitimately vanish. Report it.                                                                                                                                                                                                                                                                                                                                   |

Escalating means: run step 6's stop script if no worker pane is alive, write what happened to
`report.md`, fire the notification, and stop. Leave the worktree and the PR exactly as they are for
the user to inspect.

### Verify, don't trust

Worker sessions have claimed commits that did not exist. Before each phase transition:

- Phase 1 → 2: `gh pr view <PR> --json commits,baseRefName` — commits are real, and `baseRefName`
  equals the `base=` you were handed.
- Phase 2 → 3: one call answers both questions, for either engine — `$W/review-status.sh <PR>`:
  **did the review run?** `reviewed == true` and `reviewedSha == headSha`. Both engines post a
  marker even with zero findings. A `/moz-wide:review-pr` run that _declined_ (draft by someone
  else, repo outside seomoz) posts nothing — read the worker pane for its stated reason and escalate
  it. "Cannot establish the why" is different: the worker _asks_ and shows up as `BLOCKED` (see the
  wait table); if it instead ended with `reviewed == false` and that complaint in its pane,
  re-prompt it once with the brief's summary and acceptance criteria, then escalate if it still
  posts nothing. **did it find anything?** `inline` — the count the phase-3 skip keys on; zero means
  skip. `blocking` / `nit` / `preExisting` break it down for the report.
- Phase 3 → 4: `$W/review-status.sh <PR>` — `upToDate == false` means phase 3 committed; `true`
  means it only replied (replies never move the head).

### Escalate, never fake

Some gates only a human can clear: PR-template checkboxes attesting to manual smoke tests,
`terraform plan` needing SSO, hook-blocked operations. Collect them into `report.md` and the
notification. **Never tick an attestation checkbox** — it claims testing nobody performed.

---

## Non-obvious mechanics

| Thing                | What you need to know                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Freeing a pane       | There is no `herdr agent stop`. `herdr pane close <id>` is how a phase ends; split a new pane for the next one.                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Pane reuse           | Don't. Unsubmitted "phantom" text survives at an idle prompt, cannot be cleared with `ctrl+u`/`esc`, and the next `agent prompt` concatenates onto it.                                                                                                                                                                                                                                                                                                                                                                          |
| Repeated splits      | Always split from the **root pane**, never from the previous worker pane — chaining rightward produces unusably narrow columns.                                                                                                                                                                                                                                                                                                                                                                                                 |
| Agent names          | `[a-z][a-z0-9_-]{0,31}`, unique among _live_ agents. Closing a pane frees the name; on `name already in use`, append a digit.                                                                                                                                                                                                                                                                                                                                                                                                   |
| Coordinator cwd      | The worktree, so `gh` resolves the repo and the wait scripts work with no `GH_REPO`.                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Which repository     | The ticket's `## Repository` section, via `resolve-ticket-repo.sh`, mapped to `~/source/github.com/<owner>/<repo>` (found by origin remote when the directory name differs). The launcher's `$PWD` is a fallback only, and only when the ticket is silent.                                                                                                                                                                                                                                                                      |
| Which base           | `herdr worktree create` without `--base` starts the branch from the checkout's current `HEAD` — a feature branch someone left checked out, or a `main` nobody has pulled in a week. `resolve-base-branch.sh` fetches the default branch (or the override) from origin and returns the value to pass; `.base` is a commit rather than a name when the local branch was dirty or diverged, and never `origin/<branch>`, which would give the new branch an upstream whose name differs from its own and break a plain `git push`. |
| Docker               | Each worktree gets its own compose project and containers — not shared with your main checkout. A killed test run can leave an orphaned mocha process in _that_ worktree's container. Nothing stops them when the run ends except step 6's `stop-worktree-services.sh`; a finished run that skips it holds a full app/DB/cache stack in memory until someone notices.                                                                                                                                                           |
| `/finish-worktree`   | Acts on the worktree its own session is in and kills that pane. Out of scope here; this skill always leaves the worktree up.                                                                                                                                                                                                                                                                                                                                                                                                    |
| Two review engines   | `/moz-wide:review-pr` posts one PR _review_ (reviews endpoint) whose body carries `<!-- moz-review:v1 sha=… -->`; `/reviewing-pr` posts an issue comment carrying `<!-- reviewing-pr:sha=… -->` plus `SKILL:Reviewing-PR` inline comments. `review-status.sh` reads both — never grep for a marker by hand.                                                                                                                                                                                                                     |
| moz-wide eligibility | Skips closed/merged PRs and drafts by other authors, declines repos outside seomoz, and a re-run at an already-reviewed head posts nothing and says so. `resolve-review-skill.sh` already routes non-seomoz repos to the fallback.                                                                                                                                                                                                                                                                                              |

## Running unattended

The coordinator must never hit a permission prompt — a prompt mid-run stalls it silently until
someone looks. Beyond the rules `reviewing-pr` and `handling-pr-comments` already rely on, this
skill needs:

```jsonc
// ~/.claude/settings.json → permissions.allow
"Bash(/home/funnylookinhat/.claude/skills/handle-ticket/scripts/*)",
```

When the reviewer resolves to `/moz-wide:review-pr`, its worker also reaches for read-only Atlassian
MCP tools (Jira issue, Confluence page) on both `mcp__atlassian__*` and
`mcp__plugin_moz-wide_atlassian__*`; those are allowlisted too. An un-allowlisted MCP call in a
worker pane is a silent stall, not a graceful "skipped".

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
- **Firing the notification with the stack still up.** The worktree outlives the run by design; its
  containers and dev servers must not. Step 6 before step 7, every time.
- **Stopping after phase 3.** Handling comments changes the code the review was about; phase 4
  exists for that and terminates on `upToDate == true`.
- **Hard-coding `/reviewing-pr` or `/moz-wide:review-pr` in a worker prompt.** Resolve it with
  `resolve-review-skill.sh`; the fallback exists for repos outside seomoz and for machines without
  the plugin.
- **Counting findings with ad-hoc `gh api` greps.** The two engines post in different shapes;
  `review-status.sh` is the one place that knows both.
- **Writing the brief into the worktree.** It dirties the tree and later blocks teardown.
- **Creating the worktree from `$PWD`.** The ticket says where the work lands; the directory you
  were launched from is whatever the user had open. Resolve the repository first.
- **`herdr worktree create` without `--base`.** The branch inherits whatever is checked out in the
  main checkout. Run `resolve-base-branch.sh` and pass its `.base` every time, even when you believe
  the checkout is on an up-to-date `main`.
- **Treating a stale or unreachable origin as "good enough".** `FETCH_FAILED` stops the run. Basing
  on a week-old local `main` produces a PR whose diff includes other people's reverted work, and
  nobody notices until review.
- **Reading a base out of the ticket's prose.** "This depends on the `release/2.x` work" is context,
  not an instruction. Only a `base=` token on the invocation line, an explicit instruction to branch
  off something, or a `## Base branch` section overrides the default.
- **Guessing the repository from the ticket's prose when the section is missing.** A service name in
  the description is not a repository. `NOT_FOUND` means ask.
- **Running `/finish-worktree`.** Out of scope — the run ends with the worktree up.
