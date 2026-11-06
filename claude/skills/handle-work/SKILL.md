---
name: handle-work
description:
  Use when asked to take a piece of work described in the prompt itself (no Jira ticket) through to
  an open, reviewed pull request, hands-off, in its own isolated worktree. For work that lives in a
  Jira ticket use handle-ticket instead. Requires HERDR_ENV=1.
---

# Handle Work

One piece of work, one worktree, one coordinator that never writes code. Same shape as
`handle-ticket`, but the scope arrives **in the prompt** instead of a Jira ticket, and the run is
**decide-don't-escalate**: once the launcher has a repository and a scope, nobody is at the keyboard
until the PR is up. The work runs in a **new Herdr workspace**: its root pane holds the coordinator,
and a single pane to its right is created, used, and closed once per phase.

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

The launcher has **no** working-directory precondition beyond what step 2 says: `$PWD` is one way to
learn the repository, not a requirement.

## The two things the launcher may ask for

The launcher needs exactly two inputs: **which repository** and **what the work is**. It asks for
whichever of those it cannot determine, and for nothing else. Every other question — approach,
naming, edge cases, how far to go — is answered later by best judgement and recorded, never by
waiting for the user.

---

## Role 1 — Launch

Your whole job is to build the brief and hand off. **You do not drive the lifecycle and you do not
wait for it.** When step 7 returns, you are finished.

1. **Parse the invocation line.** Pull out these optional `key=value` tokens and remove them;
   everything that remains is the **scope text**:

   | Token                                 | Meaning                                                                                      |
   | ------------------------------------- | -------------------------------------------------------------------------------------------- |
   | `repo=OWNER/REPO` or `repo=/abs/path` | the repository (step 2)                                                                      |
   | `branch=flh/...`                      | branch name, used verbatim                                                                   |
   | `base=<ref>`                          | base branch for the worktree (default: the repo's default branch, fetched fresh from origin) |

   An explicit instruction in the scope text — "branch off `release/2.x`" — is a base override too.
   Nothing else is: the branch currently checked out, and branches the scope merely mentions as
   context, are not instructions.

   If the scope text is a single path to a readable file (a spec or notes file), its contents are
   the scope. If, after removing the tokens, the scope text is **empty or says nothing about what
   should change**, ask what the work is and stop.

2. **Resolve the repository.** Never guess from prose — a service name in the scope is not a
   repository. Checkouts live at `~/source/github.com/<owner>/<repo>`.

   ```bash
   # repo=OWNER/REPO given:
   /home/funnylookinhat/.claude/skills/handle-ticket/scripts/resolve-ticket-repo.sh /dev/null --repo OWNER/REPO
   # repo=/abs/path given, or no repo token at all:
   /home/funnylookinhat/.claude/skills/handle-ticket/scripts/resolve-ticket-repo.sh /dev/null --cwd <path-or-$PWD>
   ```

   Read `.status`, `.repo`, `.path`, and `.source` from the JSON. `$REPO_PATH` below is `.path`, and
   `.repo` is the `OWNER/REPO` the coordinator will need.

   | `.status`                | Do                                                                                                                  |
   | ------------------------ | ------------------------------------------------------------------------------------------------------------------- |
   | `OK`, `.source == "arg"` | Proceed.                                                                                                            |
   | `OK`, `.source == "cwd"` | You are inside a checkout and no `repo=` was given. That checkout is the repository; say so in the report.          |
   | `NOT_FOUND`              | No `repo=` and not inside a checkout. Ask the user for `OWNER/REPO` and stop.                                       |
   | `NOT_CLONED`             | The named repo has no checkout here. Report the clone command from `.reason` and stop — cloning is the user's call. |

   **Then resolve the base.** The new branch starts from the repository's **default branch, freshly
   fetched from origin** — never from whatever the checkout happens to have checked out. Pass
   `--base <ref>` only when step 1 found a base override.

   ```bash
   /home/funnylookinhat/.claude/skills/handle-ticket/scripts/resolve-base-branch.sh --cwd "$REPO_PATH" [--base <ref>]
   ```

   It fetches the branch from origin, fast-forwards the local branch when that is safe, and prints
   JSON. `$BASE` below is `.base` **verbatim** (a branch name, or a commit when the local branch
   could not be brought in sync), and `.branch` is the base's name for the brief and the PR.

   | `.status`                  | Do                                                                                                                                                        |
   | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `OK`                       | Proceed. Mention in the report when `.localFastForwarded` is true or `.localInSync` is false (the local branch was dirty or diverged and was left alone). |
   | `FETCH_FAILED`             | Origin is unreachable. Do not fall back to the local branch — report `.reason` and stop; a stale base silently produces a PR with the wrong diff.         |
   | `NOT_FOUND`                | The override names a branch that exists nowhere. Report it and stop.                                                                                      |
   | `NO_DEFAULT` / `NO_ORIGIN` | Report `.reason` and stop.                                                                                                                                |

3. **Name the run.** `<slug>` is a kebab-case summary of the scope, at most five words
   (`add-webhook-rate-limit`). If the scope mentions a Jira key `[A-Z][A-Z0-9]+-[0-9]+`, prefix it:
   `APDEV-6400-add-webhook-rate-limit`. `<r>` is the slug lowercased with no punctuation, truncated
   to 20 characters (`addwebhookratelimit`); it prefixes every agent name in this run. Run
   directory: `~/.claude/work-runs/<slug>/` — if it already exists, append `-2`, `-3`, … to the
   slug. Branch: `flh/<slug>` unless `branch=` was given.

4. **Write the brief** with the Write tool to `~/.claude/work-runs/<slug>/brief.md`. Put it
   **outside the repo** — the worktree must stay clean, and a dirty tree blocks teardown later.
   Sections, in order:

   ```markdown
   # <slug>

   Repository: OWNER/REPO Branch: flh/<slug> Base: <.branch from step 2> (<"default" or "override">)

   ## Scope

   <the scope text, verbatim — do not summarize or reword>

   ## Standing instructions

   - This brief is the whole specification. There is no ticket and nobody will answer questions.
   - Where the scope is ambiguous, choose the most reasonable interpretation that stays inside it
     and record the choice under an "Assumptions" heading in the PR description.
   - Follow the repository's CLAUDE.md for tests, lint, and build.
   ```

5. **Create the worktree**, **always** with `--base` — without it Herdr starts the branch from the
   checkout's current `HEAD`:

   ```bash
   herdr worktree create --cwd "$REPO_PATH" --branch flh/<slug> --base "$BASE" --no-focus
   ```

   Capture `.result.root_pane.pane_id`, `.result.workspace.workspace_id`, and
   `.result.worktree.path` from the JSON. Never guess an ID.

6. **Start the coordinator in the root pane** — the root pane is already an available shell; do not
   split it:

   ```bash
   herdr agent start <r>-coord --kind claude --pane <root-pane-id>
   ```

7. **Hand off, fire-and-forget** — no `--wait`:

   ```bash
   herdr agent prompt <r>-coord '/handle-work --coordinate run=<slug> brief=<abs-brief-path> repo=<OWNER/REPO> branch=flh/<slug> base=<.branch from step 2> worktree=<path> pane=<root-pane-id> workspace=<workspace-id>'
   ```

   Expand `~` yourself — every path in that prompt must be **absolute**. It arrives as text in
   another agent's prompt box, where no shell expands it and a `~` path is not readable.

8. **Report** repository (and whether it came from `repo=` or from `$PWD`), branch, base (and
   whether it was the default or an override, and whether the local branch was fast-forwarded or
   left alone), worktree path, workspace ID, coordinator agent name, and that results will arrive as
   a Herdr notification plus `~/.claude/work-runs/<slug>/report.md`. Then stop.

---

## Role 2 — Coordinate

You are in the worktree's root pane. **You never write the work's code** — every phase runs in a
worker session in the pane to your right. Read the brief first, and confirm
`git rev-parse --show-toplevel` matches the `worktree=` you were given.

Keep running notes in `~/.claude/work-runs/<slug>/notes.md` as phases complete, including **every
judgement call you make** (see "Decide, don't escalate" below).

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

This skill ships no scripts of its own; it uses `handle-ticket`'s. Call them by **absolute path** —
your cwd is the worktree, so a relative `scripts/…` resolves to a file that does not exist, and it
would miss the allowlist glob and prompt. Write `$W` below in full:

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

1. **Implement** — agent `<r>-impl`. Prompt: the brief's full text, then:

   > You are running unattended; nobody will answer questions, so do not ask any. Plan the work
   > first, then execute it. Where the scope is ambiguous, choose the most reasonable interpretation
   > that stays inside it, keep going, and list each choice under an "Assumptions" heading in the PR
   > description. Follow this repo's CLAUDE.md for tests, lint, and build; commit with conventional
   > commits; push; open a PR with `gh pr create --base <base>` whose description explains what
   > changed and why.

   `<base>` is the `base=` you were handed, so a run based on a release branch does not open its PR
   against the default branch.

   Wait on: `$W/wait-for-pr.sh <branch> <r>-impl`.

2. **Review** — agent `<r>-review`, prompt `$REVIEW <PR>` followed by one line of invoker context —
   the brief's scope in a sentence — so the reviewer can state the PR's purpose without asking (e.g.
   `/moz-wide:review-pr https://github.com/seomoz/<repo>/pull/<n> — purpose: <one sentence from the brief>`).
   Wait on: `$W/wait-for-agent.sh <r>-review`.

3. **Handle comments** — agent `<r>-comments`, prompt `/handling-pr-comments <PR>`. Wait on:
   `$W/wait-for-agent.sh <r>-comments`. **Skip this phase entirely if `review-status.sh` reports
   `inline == 0`** — go straight to phase 5. Spinning up a session to handle nothing costs minutes
   and a pane. Any inline finding counts, `[pre-existing]` ones included — the handling skill
   decides per thread.

4. **Re-review if phase 3 committed.** Run `$W/review-status.sh <PR>`. `upToDate == false` means the
   head moved past the sha the review covered — run `$REVIEW <PR>` again as `<r>-review2` (then
   `<r>-review3`, … on later passes; both engines re-review incrementally on their own), then re-run
   `review-status.sh` and loop back to 3 if the new review has `inline > 0`. **Stop looping** when
   `upToDate == true` (replies alone never move the head, so a phase 3 that only replied ends here),
   or when the only new commits are docs/comment clarifications that assert nothing new — say so
   rather than looping again.

5. **Check CI.** `gh pr checks <PR>`; if any check is still pending, `gh pr checks <PR> --watch`
   returns once they settle. Green → phase 6. Red → **one** fix attempt, at most once per run: agent
   `<r>-ci`, prompt "CI is red on <PR>. Read the failing checks (`gh pr checks`,
   `gh run view --log-failed`). If this branch caused the failure, fix it, commit, and push. If it
   is pre-existing, flaky, or infrastructure, change nothing and say which." Wait on
   `$W/wait-for-agent.sh <r>-ci`. If it pushed, the head moved: run the phase 3 ↔ 4 loop again as
   normal (it still ends on `upToDate == true`), then re-run `gh pr checks`. Whatever colour it is
   now is what you report — the "once" limits the CI-fix worker, not the review loop. **Never report
   success on a red check.**

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

7. **Report and stop.** Write `~/.claude/work-runs/<slug>/report.md` (PR URL, what each phase did,
   every judgement call with its reasoning, CI state, anything escalated), then:
   ```bash
   herdr notification show '<slug> ready' --body 'PR #<n> reviewed; CI <state>' --sound done
   ```
   **Leave the worktree up.** Do not run `/finish-worktree`, `herdr worktree remove`, or close your
   own pane — the user tears it down when they are ready.

### Decide, don't escalate

The user launched this to come back to a finished PR. A worker that stops to ask is answered by
**you**, from the brief and your own judgement — not parked until someone looks. When a wait reports
`BLOCKED`:

1. `herdr agent read <agent> --source recent-unwrapped --lines 120` — read the actual question.
2. Decide. Prefer the interpretation that is **smallest, reversible, and inside the brief's scope**.
   If the brief settles it, say so; if it does not, pick and say why.
3. `herdr agent prompt <agent> '<your answer>'` — one clear answer, no hedging, no "whichever you
   prefer".
4. Append the question, your answer, and your reasoning to `notes.md`; it goes in `report.md` under
   **Judgement calls** at the end.
5. Re-arm the same wait script. Answering a question does not end the phase.

| Worker asks                                                 | You answer                                                                             |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| "Option A or B?" on approach, naming, structure, test depth | Pick one. Smaller and more conventional for this repo wins.                            |
| "Should I also do X?" where X is outside the scope          | No. Note it as follow-up work in the report.                                           |
| "The scope could mean X or Y"                               | Whichever the scope's wording supports more; if equal, the one with less blast radius. |
| `/moz-wide:review-pr` cannot state the PR's purpose         | The brief's scope, in a sentence; the review records it as `invoker-supplied`.         |

**Hard limits — the only things you never do on the user's behalf:**

- Tick an attestation checkbox in a PR template claiming manual tests, smoke tests, or sign-off that
  nobody performed. A worker asking whether to tick one is answered "no, leave it unchecked and
  continue"; the unchecked box is listed in `report.md` for the user to clear. Escalate only if the
  run cannot proceed without it ticked.
- Clear credentials, SSO, or MFA prompts (`terraform plan` wanting a login, a hook demanding a
  token).
- Approve a permission prompt in the worker pane. Typing an approval into another session's
  permission dialog is what the allowlist exists to prevent; report what was asked.
- Anything irreversible outside the branch: force-pushing a shared branch, deleting remote branches
  or tags, touching production data or infrastructure.
- Invent work the brief asks for that this repository cannot contain.

When one of these is the only way forward, escalate: run step 6's stop script if no worker pane is
alive, write it to `report.md`, fire the notification, and stop with the worktree and PR left
exactly as they are. Everything else is yours to decide.

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

| Line                       | Meaning                        | Do                                                                                                                                                               |
| -------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PR_OPEN <branch> #<n>`    | the PR exists                  | Verify commits, then advance.                                                                                                                                    |
| `DONE` / `SETTLED <agent>` | the turn is over               | Verify the phase's artifact, then advance.                                                                                                                       |
| `BLOCKED <agent>`          | the worker is waiting on input | Read the pane and **answer it** per "Decide, don't escalate". Escalate only for the listed exceptions.                                                           |
| `STALLED <agent>`          | idle ~15 min, no PR            | Read the pane. If it is a question, answer it. If it is silent, one nudge prompt ("continue; open the PR when done") is fair; a second `STALLED` means escalate. |
| `GONE <agent>`             | not resolvable                 | The session or pane died. **Never treat this as success** — this skill never removes a worktree, so nothing should legitimately vanish. Report it.               |

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
  it. If it ended with `reviewed == false` complaining it cannot establish the why, re-prompt it
  once with the brief's scope as the purpose, then escalate if it still posts nothing. **did it find
  anything?** `inline` — the count the phase-3 skip keys on; zero means skip. `blocking` / `nit` /
  `preExisting` break it down for the report.
- Phase 3 → 4: `$W/review-status.sh <PR>` — `upToDate == false` means phase 3 committed; `true`
  means it only replied (replies never move the head).

---

## Non-obvious mechanics

| Thing                | What you need to know                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Freeing a pane       | There is no `herdr agent stop`. `herdr pane close <id>` is how a phase ends; split a new pane for the next one.                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Pane reuse           | Don't. Unsubmitted "phantom" text survives at an idle prompt, cannot be cleared with `ctrl+u`/`esc`, and the next `agent prompt` concatenates onto it.                                                                                                                                                                                                                                                                                                                                                                          |
| Repeated splits      | Always split from the **root pane**, never from the previous worker pane — chaining rightward produces unusably narrow columns.                                                                                                                                                                                                                                                                                                                                                                                                 |
| Agent names          | `[a-z][a-z0-9_-]{0,31}`, unique among _live_ agents. Closing a pane frees the name; on `name already in use`, append a digit.                                                                                                                                                                                                                                                                                                                                                                                                   |
| Coordinator cwd      | The worktree, so `gh` resolves the repo and the wait scripts work with no `GH_REPO`.                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Which repository     | `repo=` on the invocation line, else the checkout `$PWD` is in, else ask. `resolve-ticket-repo.sh` with `/dev/null` as the ticket file does the mapping to `~/source/github.com/<owner>/<repo>` (found by origin remote when the directory name differs).                                                                                                                                                                                                                                                                       |
| Which base           | `herdr worktree create` without `--base` starts the branch from the checkout's current `HEAD` — a feature branch someone left checked out, or a `main` nobody has pulled in a week. `resolve-base-branch.sh` fetches the default branch (or the override) from origin and returns the value to pass; `.base` is a commit rather than a name when the local branch was dirty or diverged, and never `origin/<branch>`, which would give the new branch an upstream whose name differs from its own and break a plain `git push`. |
| Shared scripts       | Everything under `handle-ticket/scripts` is engine-agnostic; nothing in it reads Jira. Keeping one copy means one allowlist entry and no drift.                                                                                                                                                                                                                                                                                                                                                                                 |
| Docker               | Each worktree gets its own compose project and containers — not shared with your main checkout. A killed test run can leave an orphaned mocha process in _that_ worktree's container. Nothing stops them when the run ends except step 6's `stop-worktree-services.sh`; a finished run that skips it holds a full app/DB/cache stack in memory until someone notices.                                                                                                                                                           |
| `/finish-worktree`   | Acts on the worktree its own session is in and kills that pane. Out of scope here; this skill always leaves the worktree up.                                                                                                                                                                                                                                                                                                                                                                                                    |
| Two review engines   | `/moz-wide:review-pr` posts one PR _review_ (reviews endpoint) whose body carries `<!-- moz-review:v1 sha=… -->`; `/reviewing-pr` posts an issue comment carrying `<!-- reviewing-pr:sha=… -->` plus `SKILL:Reviewing-PR` inline comments. `review-status.sh` reads both — never grep for a marker by hand.                                                                                                                                                                                                                     |
| moz-wide eligibility | Skips closed/merged PRs and drafts by other authors, declines repos outside seomoz, and a re-run at an already-reviewed head posts nothing and says so. `resolve-review-skill.sh` already routes non-seomoz repos to the fallback.                                                                                                                                                                                                                                                                                              |

## Running unattended

The coordinator must never hit a permission prompt — a prompt mid-run stalls it silently until
someone looks. This skill calls only `handle-ticket`'s scripts, so the existing allowlist entry
covers it:

```jsonc
// ~/.claude/settings.json → permissions.allow
"Bash(/home/funnylookinhat/.claude/skills/handle-ticket/scripts/*)",
```

When the reviewer resolves to `/moz-wide:review-pr`, its worker also reaches for read-only Atlassian
MCP tools on both `mcp__atlassian__*` and `mcp__plugin_moz-wide_atlassian__*`; those are allowlisted
too. An un-allowlisted MCP call in a worker pane is a silent stall, not a graceful "skipped".

Run each `herdr`, `git`, and `gh` command as its own Bash call — a compound line (`cd … && …`,
`a; b`) is matched as one blob and prompts no allowlist entry can cover.

## Common mistakes

- **Asking a third question at launch.** Repository and scope are the only inputs the launcher may
  ask for. "Which approach?", "should tests cover X?", "what should it be called?" are judgement
  calls for the run, not questions for the user.
- **`herdr worktree create` without `--base`.** The branch inherits whatever is checked out in the
  main checkout. Run `resolve-base-branch.sh` and pass its `.base` every time, even when you believe
  the checkout is on an up-to-date `main`.
- **Treating a stale or unreachable origin as "good enough".** `FETCH_FAILED` stops the run. Basing
  on a week-old local `main` produces a PR whose diff includes other people's reverted work, and
  nobody notices until review.
- **Reading a base out of the scope's prose.** "This depends on the `release/2.x` work" is context,
  not an instruction. Only a `base=` token or an explicit instruction to branch off something
  overrides the default.
- **Escalating a worker's question that the brief or common sense answers.** Read it, decide,
  answer, note it. Escalation is for the five listed exceptions only.
- **Answering a worker with a menu.** "Either is fine" sends it straight back to `BLOCKED`.
- **Coordinating from the launcher session.** The launcher's job ends at the handoff; the
  coordinator lives in the new workspace's root pane.
- **`agent prompt --wait`.** It looks like the simple way to sequence phases and costs you the
  entire phase's wall-clock inside one turn. Use Monitor.
- **Leaving worker panes open.** Four panes across a workspace are unreadable, and the next phase's
  "clean context" is only clean because the previous pane is gone.
- **Reporting done without `gh pr checks`.** A green-looking review says nothing about CI.
- **Firing the notification with the stack still up.** The worktree outlives the run by design; its
  containers and dev servers must not. Step 6 before step 7, every time.
- **A second CI-fix phase.** One attempt; after that, red is reported as red.
- **Stopping after phase 3.** Handling comments changes the code the review was about; phase 4
  exists for that and terminates on `upToDate == true`.
- **Hard-coding `/reviewing-pr` or `/moz-wide:review-pr` in a worker prompt.** Resolve it with
  `resolve-review-skill.sh`.
- **Counting findings with ad-hoc `gh api` greps.** `review-status.sh` is the one place that knows
  both engines' shapes.
- **Writing the brief into the worktree.** It dirties the tree and later blocks teardown.
- **Rewording the scope in the brief.** The implementer gets the user's words, verbatim; a
  paraphrase is the first unrecorded assumption of the run.
- **Running `/finish-worktree`.** Out of scope — the run ends with the worktree up.
