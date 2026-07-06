---
name: reviewing-pr
description:
  Use when asked to code-review a GitHub pull request and post the findings onto the PR — either a
  first full review of the whole PR, or a follow-up that reviews only what changed since the skill's
  last review.
---

# Reviewing PR

## Overview

Run the built-in **code-review** skill against a GitHub PR, then post its findings **onto the PR**
as inline review comments (one per finding) plus one summary comment. Each comment is stamped
`SKILL:Reviewing-PR` so a later run — and the [[handling-pr-comments]] skill — can recognize its own
trail.

Two modes, chosen automatically by `scripts/review-state.sh`:

- **full** — the PR has never been reviewed by this skill. Review and post on the whole PR diff.
- **incremental** — the skill reviewed before, AND either the author pushed new commits or
  `handling-pr-comments` posted replies since. Review the whole diff but post **only** findings on
  lines changed since the last review.
- **none** — reviewed before, nothing changed since. Report and stop.

**Core principle:** never re-litigate code you already commented on. The sha of each review is
recorded in a hidden marker; the next run diffs from there.

## Inputs

The PR is given as a URL (`https://github.com/OWNER/REPO/pull/N`), `OWNER/REPO#N`, or a bare number
in the current repo. The bundled scripts accept any of these forms verbatim — pass the reference
straight through.

## Tool discipline (run unattended, no prompts)

The three bundled scripts are allowlisted as a group (see
[Running unattended](#running-unattended)), so each runs without a prompt **only when invoked as its
own standalone command**. Everything else uses read-only built-in tools, which never prompt:

| To…                                       | Use                               | NOT                     |
| ----------------------------------------- | --------------------------------- | ----------------------- |
| read a file                               | **Read**                          | `cat`, `head`, `sed -n` |
| search file contents / find a line number | **Grep**                          | `grep -rn`, `rg`        |
| find files by name                        | **Glob**                          | `find`, `ls`            |
| write `findings.json` / `review.json`     | **Write** (to the scratchpad dir) | `echo >`, heredocs      |

Rules that keep the run prompt-free:

- **One command per Bash call.** Never chain the allowlisted commands with `&&`, `;`, or a leading
  `cd` — a compound line is matched as one blob and prompts. If you need a working directory, `cd`
  into the repo as its own call first (it persists); then run each script/`git`/`gh` command on its
  own.
- **Take anchors from code-review, don't hunt for them.** Every finding from `ReportFindings`
  already carries `file` and `line` — use them directly. Do **not** `grep -n`/open files to
  re-derive line numbers; that's wasted work and an extra prompt surface.
- **Write JSON to the scratchpad, not the repo.** Put `findings.json`/`review.json` under your
  session scratchpad dir (writes there are pre-approved) — never in the PR's working tree, so the
  review leaves no stray files behind.
- **Never route findings through `echo`.** code-review bodies contain newlines and backticks that
  shells mangle. Build every JSON file with the **Write tool**.

## Workflow

### 0. Check out the PR's head branch

```bash
gh pr checkout N --repo OWNER/REPO   # or: gh pr checkout <url>
```

The working tree must be the PR head so (a) code-review reviews the PR's changes and (b) the
incremental diff is computable locally. `gh pr checkout` also wires the correct upstream for fork
PRs.

### 1. Decide the mode

```bash
scripts/review-state.sh <pr>
```

Returns one JSON object:
`{ owner, repo, pr, headSha, baseRef, baseSha, reviewed, lastReviewedSha, newCommitsSince, handlingRepliesSince, mode }`.

- **`mode == "none"`** → stop. Report "already reviewed `headSha`, nothing changed since." Do not
  post.
- **`mode == "full"`** → go to step 2, review the whole PR.
- **`mode == "incremental"`** → go to step 2, then filter with `lastReviewedSha` in step 4.

(The script reads resolution/marker state via `gh api`; it's the single source of the decision —
read it if you need to extend the fields.)

### 2. Run the built-in code-review skill

Invoke the **code-review** skill (via the Skill tool). **Do NOT pass `--comment` or `--fix`** —
`--comment` posts un-prefixed comments and bypasses incremental filtering; you post yourself in
step 5. Pass through the effort level the caller asked for (default: no flag).

code-review reports each issue through the `ReportFindings` tool. Collect, for every finding: its
`file`, `line`, and a one-paragraph body built from `summary` + `failure_scenario`. If code-review
reports **no** findings, skip to step 5 with an empty `findings` array (the summary comment still
posts, advancing the marker).

### 3. Write `findings.json`

With the **Write tool**, write the collected findings to a JSON file **in your session scratchpad
dir** (not the repo). The `path` field is repo-relative, matching what code-review reported; the
`line` comes straight from the finding — do not re-derive it:

```json
[
  {
    "path": "src/foo.py",
    "line": 88,
    "body": "Off-by-one: the loop reads index len, one past the end — raises IndexError when the list is non-empty."
  },
  { "path": "src/bar.py", "line": 12, "body": "..." }
]
```

Keep each `body` concise and specific — what's wrong and why it matters. Do **not** add the
`SKILL:Reviewing-PR` prefix yourself; the post script does that idempotently.

### 4. Incremental only — filter to changed lines

```bash
scripts/filter-incremental-findings.sh <lastReviewedSha> <headSha> findings.json > review-findings.json
```

Keeps only findings on lines added/changed in `lastReviewedSha..headSha`; drops findings on
already-reviewed code. For a **full** review, skip this — use `findings.json` directly. (If the
script reports `commit not found locally`, run `git fetch` and retry.)

### 5. Post the review

Build `review.json` with the **Write tool** (in the scratchpad dir) — a `findings` array (from step
3 or 4) and an optional `summary`:

```json
{
  "summary": "Reviewed the auth refactor — 2 issues on the token path.",
  "findings": [{ "path": "src/foo.py", "line": 88, "body": "..." }]
}
```

Then post everything in one call (preview first with `--dry-run`):

```bash
scripts/post-review.sh --dry-run <pr> <headSha> review.json   # preview
scripts/post-review.sh <pr> <headSha> review.json             # post
```

The script posts one inline comment per finding (anchored to `headSha`) and one summary issue
comment carrying `<!-- reviewing-pr:sha=<headSha> -->` — the marker the next run reads. It
**auto-prefixes every body with `SKILL:Reviewing-PR` + two newlines** (idempotent) — do not add it
yourself. Omit `summary` and the script writes a sensible default. GitHub rejects inline comments on
lines not in the PR diff; those report `FAILED` per line but don't abort the run.

**Leave threads unresolved** — the author (or `handling-pr-comments`) acts on them.

## Quick reference

| Step               | Command                                                                            |
| ------------------ | ---------------------------------------------------------------------------------- |
| Checkout           | `gh pr checkout N --repo OWNER/REPO`                                               |
| Decide mode        | `scripts/review-state.sh <pr>` → `{ mode, headSha, lastReviewedSha, … }`           |
| Get findings       | run **code-review** skill (no `--comment`/`--fix`); collect from `ReportFindings`  |
| Write findings     | **Write tool** → `findings.json` (`[{path,line,body}]`)                            |
| Incremental filter | `scripts/filter-incremental-findings.sh <lastReviewedSha> <headSha> findings.json` |
| Post               | **Write** `review.json`, then `scripts/post-review.sh <pr> <headSha> review.json`  |

## Running unattended

The whole workflow is designed to run without approval prompts. It relies on these allow rules
(mirrors the `handling-pr-comments` setup):

```jsonc
// ~/.claude/settings.json → permissions.allow
"Bash(/home/funnylookinhat/.claude/skills/reviewing-pr/scripts/*)",  // all three scripts, incl. real posting
"Skill(code-review)",                                                // invoke the review skill
// already present and relied on:
"Bash(gh pr:*)",            // gh pr checkout
"Bash(git diff:*)", "Bash(git -C * diff *)", "Bash(git blame:*)",    // code-review's finder agents
"Write(//tmp/**)"           // findings.json / review.json in the scratchpad
```

The scripts glob auto-allows `post-review.sh` **actually posting** to GitHub. To require a human
confirmation before comments hit a PR, replace the glob with per-script rules and gate posting to
dry-run only:

```jsonc
"Bash(/home/funnylookinhat/.claude/skills/reviewing-pr/scripts/review-state.sh:*)",
"Bash(/home/funnylookinhat/.claude/skills/reviewing-pr/scripts/filter-incremental-findings.sh:*)",
"Bash(/home/funnylookinhat/.claude/skills/reviewing-pr/scripts/post-review.sh --dry-run *)",
```

If a command still prompts, it was almost certainly **chained** (`cd … && …`, `a; b`) — split it
into standalone Bash calls so the allowlist can match each one.

## Common mistakes

- **Passing `--comment` to code-review** — posts un-prefixed comments and skips incremental
  filtering. Run code-review plain; post with `post-review.sh`.
- **Posting in `full` mode when state says `incremental`** — you re-comment on already-reviewed
  (maybe already-handled) code. Always run `review-state.sh` first and honor `mode`.
- **Skipping the summary comment** — it carries the sha marker. Without it the next run can't tell
  what was already reviewed and falls back to full. `post-review.sh` always posts it; don't suppress
  it.
- **Building JSON with `echo`/heredocs** — mangles newlines/backticks in finding bodies. Use the
  Write tool.
- **Committing to a new branch instead of `gh pr checkout`** — code-review then reviews the wrong
  diff and inline anchors won't match the PR.
- **Adding the `SKILL:Reviewing-PR` prefix by hand** — `post-review.sh` applies it idempotently;
  doing both is fine but unnecessary.

## Note on the handling-pr-comments prefix

`review-state.sh` detects follow-up activity by the prefix `handling-pr-comments` stamps its replies
with — currently **`SKILL:Handling-PR-Comments`** (see that skill's `scripts/post-replies.sh`). If
that skill's prefix ever changes, override detection with
`HANDLING_PREFIX=… scripts/review-state.sh <pr>`.
