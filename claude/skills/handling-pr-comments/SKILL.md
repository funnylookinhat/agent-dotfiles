---
name: handling-pr-comments
description:
  Use when asked to address, respond to, work through, or "handle" the open/unresolved review
  comments on a GitHub pull request — deciding per comment whether to make the code change or reply,
  then committing and posting replies.
---

# Handling PR Comments

## Overview

Work through the **unresolved review threads** on a GitHub PR. For each thread, read the _whole_
thread and decide one of three outcomes: **fix** (make the code change), **reply** (ask/clarify/push
back), or **no-action** (already handled, outdated, or a declined nitpick). Make **one commit** for
all fixes, push it, then reply to each addressed thread with the commit hash. Leave threads
unresolved for the author to verify.

**Core principle:** Don't blindly implement. A review comment can be wrong, ambiguous, or already
moot — read the full thread and judge before touching code.

**REQUIRED BACKGROUND:** The per-thread decision (Step 2) and the reply wording (Step 5) are
governed by superpowers:receiving-code-review — review comments are external feedback to _evaluate_,
not orders to follow. Because analysis subagents do NOT auto-load skills, this skill carries that
skill's checklist and wording rules inline into the subagent prompt.

## Inputs

The PR is given as a URL (`https://github.com/OWNER/REPO/pull/N`) or `OWNER/REPO#N` or just a number
in the current repo. Resolve it to `OWNER`, `REPO`, `N` before starting.

## The critical gotcha

**Resolved/unresolved state exists ONLY in the GraphQL API**, on `reviewThreads.isResolved`.
`gh pr view --comments` and the REST `/pulls/N/comments` endpoint do **not** expose it. If you
enumerate comments any other way you cannot honor "unresolved only" — you will act on
already-resolved threads. Always enumerate via GraphQL.

## Tool discipline (avoid permission prompts)

Reading and searching the codebase is most of this skill's work. Do it with the **built-in tools**,
which are read-only and never prompt — NOT by shelling out, which prompts on every call (and a
compound `for … ; grep … ; sed …` line prompts as one blob no allowlist can match). This applies in
the main session and in every analysis subagent.

| To…                              | Use                                  | NOT                              |
| -------------------------------- | ------------------------------------ | -------------------------------- |
| read a file                      | **Read**                             | `cat`, `head`, `tail`, `sed -n`  |
| search file contents             | **Grep**                             | `grep -rn`, `rg`, `echo && grep` |
| find files by name/glob          | **Glob**                             | `find`, `ls`                     |
| change a file (incl. rename-all) | **Edit** (`replace_all`) / **Write** | `sed -i`, `echo >`, `>>`         |

Batch independent Read/Grep/Glob calls in parallel. Reserve **Bash** for what only it can do: the
bundled `scripts/*.sh`, `git`, `gh`, and the project's build/test/lint commands. Those legitimately
prompt — allowlist them if you like, but never route file reads/searches through Bash to work around
a prompt.

## Workflow

### 0. Check out the PR's head branch

```bash
gh pr checkout N --repo OWNER/REPO   # or: gh pr checkout <url>
```

Your commit must land on the PR's **head branch** so it appears on the PR. Do NOT
`git checkout -b <new-branch>` — a new branch is not the PR and the commit won't show up.
`gh pr checkout` also wires up the correct upstream for fork PRs, so the later `git push` targets
the fork.

### 1. Enumerate unresolved threads

Use the bundled script — it handles the GraphQL query, pagination, and the `isResolved == false`
filter, and prints a clean JSON array:

```bash
scripts/list-unresolved-threads.sh <pr>   # pr = URL | OWNER/REPO#N | N (current repo)
```

Each element:
`{ threadId, anchorId, path, line, isOutdated, comments:[{author,createdAt,databaseId,body,diffHunk}] }`.
Consume it by piping to `jq` or saving to a file — do NOT round-trip it through `echo "$var"` (some
shells mangle `\n`/`\t` inside the diff hunks).

- **`anchorId`** is the first comment's `databaseId` — the reply target. Replying to a later comment
  can 422 or detach.
- **`comments`** is the full ordered thread — feed all of it to the analyzer, not just the last.
- **`isOutdated`** does NOT mean resolved; the script already filtered on `isResolved`, so treat
  every returned thread as open.

(The script is the single source of the GraphQL query — read it if you need to extend the fields.)

### 2. Analyze each thread — parallel Opus subagents

For more than ~2 threads, dispatch one **read-only** analysis subagent per thread with `model: opus`
(judgment is the hard part). See superpowers:dispatching-parallel-agents. For 1–2 threads, analyze
inline.

Give each subagent: the full thread (all comments, in order), the file path/line, and repo access to
read surrounding code. Instruct it **not to edit** — only to return a decision, and to read/search
with the Read/Grep/Glob tools per **Tool discipline** above (it can't load this skill, so state that
in its prompt). Because it can't load skills, the subagent prompt MUST also include the
receiving-code-review evaluation checklist below. Force this structured return:

```json
{ "anchorId": <first-comment databaseId>,
  "decision": "fix" | "reply" | "no-action",
  "rationale": "why",
  "change": "for fix: files + precise edits to make",
  "reply": "for fix/reply: the reply text to post" }
```

**Evaluate before deciding** (from superpowers:receiving-code-review — a review comment is a
suggestion to verify, not an order). Check the surrounding code and ask:

- Is it technically correct for THIS codebase/stack?
- Would it break existing behavior, or is there a reason for the current implementation?
- Is it YAGNI — does the suggested code/feature actually get used? (grep before adding)
- Does the reviewer have the full context, or are they missing something?

**Decision rule** (apply after reading the WHOLE thread — a later comment often supersedes the
opening ask):

| Outcome       | When                                                                                                                                                                                                         |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **fix**       | Concrete change that passes the checks above; agreed and not retracted later in the thread.                                                                                                                  |
| **reply**     | Question; ambiguous ask (clarify, don't guess); a suggestion that fails a check — is wrong, breaks something, or is YAGNI (push back with technical reasoning, not defensiveness); out of scope for this PR. |
| **no-action** | Praise; already addressed elsewhere; moot/outdated; a nitpick you're declining. No reply needed unless a short note helps.                                                                                   |

### 3. Apply fixes in the main session (never in parallel)

Collect all `fix` results and apply the edits yourself, sequentially, in the working tree. Do NOT
let subagents edit — parallel writes to one working tree collide and can't produce a single clean
commit. Fixes may be interdependent; apply them coherently.

If a fix is a bug fix, follow superpowers:test-driven-development. **Verify before committing** —
run the repo's tests/lint/build (superpowers:verification-before-completion).

### 4. One commit, then push, then VERIFY visibility

```bash
git add -A
git commit -m "Address PR #N review feedback

- <one line per addressed thread>"
git push                                   # fork PR: gh set the upstream at checkout; push goes to the fork
SHA=$(git rev-parse HEAD)
gh api repos/OWNER/REPO/commits/$SHA --jq .sha   # must echo $SHA; 404 => not visible yet, do NOT reply
```

Push **before** replying — a hash that isn't on the remote is a dead link for the reviewer. Verify
it resolves before posting.

### 5. Post all replies with the bundled script

Do NOT hand-write a one-off reply script in the scratchpad (its path changes every run, so it can
never be allowlisted, and it re-implements escaping you can get wrong). Instead: build a
`replies.json` with the **Write tool** (no prompt), then post them all with one call to the bundled
script.

`replies.json` — one entry per addressed thread (fix AND reply-only; omit no-action threads):

```json
[
  {
    "anchorId": 3523200125,
    "body": "Fixed in OWNER/REPO@<sha> — read the apikey header into `{ apikey_id }`."
  },
  {
    "anchorId": 3523200127,
    "body": "Left as-is — this path is already guarded upstream, so the change would be redundant."
  }
]
```

```bash
scripts/post-replies.sh <pr> path/to/replies.json          # posts every reply, threaded on anchorId
scripts/post-replies.sh --dry-run <pr> path/to/replies.json # preview without posting
```

`anchorId` is the value from `list-unresolved-threads.sh` (the thread's first comment). The script
threads each reply correctly and reports one ok/FAILED line per entry. It also **auto-prefixes every
reply with `SKILL:Handling-PR-Comments` + two newlines** — do NOT add that prefix to the `body`
fields yourself.

**Wording** (from superpowers:receiving-code-review): each `body` states the fix or gives technical
reasoning. Use `OWNER/REPO@SHA` (full sha) so GitHub renders a clickable commit link. No
performative agreement and no gratitude — no "You're absolutely right!", "Great point!", or "Thanks
for catching that!". "Good catch — <specific issue>" is fine; a bare "Thanks" is not. Actions speak;
the commit shows you heard.

**Leave threads unresolved** — the author verifies and resolves. (Do not call `resolveReviewThread`
unless explicitly asked.)

## Quick reference

| Step                      | Command                                                                |
| ------------------------- | ---------------------------------------------------------------------- |
| Enumerate unresolved      | `scripts/list-unresolved-threads.sh <pr>` → JSON array of open threads |
| Read / search / find code | Read / Grep / Glob tools — never `cat`/`grep`/`find` in Bash           |
| Reply anchor              | first comment's `databaseId` (`anchorId` from the enum script)         |
| Read full thread          | all `comments`, in order — not just the last                           |
| Commit                    | one `git commit` for all fixes                                         |
| Verify pushed             | `gh api repos/O/R/commits/$SHA --jq .sha` before replying              |
| Post replies              | write `replies.json`, then `scripts/post-replies.sh <pr> replies.json` |

## Common mistakes

- **Using `gh pr view --comments` / REST to find "open" comments** — no resolution state; you'll act
  on resolved threads. GraphQL only.
- **Replying with a local, unpushed hash** — push and verify visibility first.
- **Committing to a new branch (`git checkout -b ...`)** — the commit won't be on the PR. Use
  `gh pr checkout N` first and commit onto the PR's head branch.
- **Multiple commits** — spec is one commit for all fixes.
- **Replying to the last comment's id** instead of the thread's first comment — breaks threading.
- **Editing in parallel subagents** — collides on the working tree; analyze in parallel, edit in the
  main session.
- **Implementing a comment you didn't understand or disagree with** — clarify or push back instead.
- **Treating `isOutdated` as resolved** — it isn't.
- **Shelling out for reads/searches** (`cat`, `grep -rn`, `find`, `sed -i`) — prompts every time;
  use Read/Grep/Glob/Edit (see Tool discipline).
- **Hand-writing a reply script in the scratchpad** — its path changes each run so it can't be
  allowlisted; use `scripts/post-replies.sh` with a Write-tool `replies.json`.
