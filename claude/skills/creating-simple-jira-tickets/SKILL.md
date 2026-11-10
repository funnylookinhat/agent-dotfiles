---
name: creating-simple-jira-tickets
description:
  Use when creating a simple, lightweight, quick, stub, or placeholder Jira ticket — little is known
  about the work yet, most of it is investigation or a spike, or the ticket only needs to hold a
  spot on the board. Triggers include "simple ticket", "quick ticket", "placeholder ticket", "stub
  ticket", "just get a ticket in", "ticket to look into X". For fully specified work, use
  creating-jira-tickets instead.
---

# Creating Simple Jira Tickets

## Overview

A simple ticket records that work exists, where it lands, and the little that is known about it. It
is short on purpose: the detail does not exist yet, and finding it is part of the work.

Core principle: **the ticket holds only what the user said.** A gap stays a gap, or becomes a
question under "To Investigate".

## When NOT to Use

- The work is already well understood → `creating-jira-tickets`
- The user wants to be questioned for detail → `creating-detailed-jira-tickets`
- The ticket already exists → `refining-jira-tickets`

## Workflow

### 1. Find a repository candidate

Stop at the first that answers:

1. The user named a repository.
2. The request names a service whose checkout exists at `~/source/github.com/<owner>/<repo>/` — an
   `ls ~/source/github.com/*/` match on the name.
3. The current directory is inside a git checkout: `git remote get-url origin`.
4. No candidate. Offer "not known yet" as the default.

Verify a candidate with `gh repo view <owner/repo> --json name`. Do not grep across checkouts or
read code to find one: for a ticket about locating something, that search is the ticket's own work.

### 2. Ask the basics

Ask once, in a single message, offering defaults from CLAUDE.md and the conversation where they
exist:

- **Project key**
- **Issue type** — default Task, including when the work is investigating a malfunction. Bug only
  when the user calls it a bug.
- **Repository** — the step-1 candidate to confirm, or "not known yet"
- **Parent epic** (optional)
- **Capitalizable** (yes/no) — sets the ticket's "Account" field (step 4)
- **What are we doing and why?** (optional)

Ask nothing about requirements, acceptance criteria, edge cases, or scope.

### 3. Draft

The description is these sections, in this order:

```
## What are we doing and why?
<the user's rationale>

## Repository
<one of the three forms below>

## Summary
<one to three sentences>

## To Investigate
- <question>

## Done When
- <one or two bullets>

## Notes
- <reference material>
```

Repository and Summary and Done When are always present. The other three are present only under the
condition given for each below.

**What are we doing and why?** — present when the user gave a rationale. Their words, lightly
edited.

**Repository** — the form that matches the answer from step 2:

| Answer                                                                    | Section body                                                                                                                | `**Repository:**` line in the review block |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| A confirmed `owner/repo`                                                  | `` `owner/repo` — https://github.com/owner/repo `` then, on its own line, `Work for this ticket starts in this repository.` | `owner/repo`                               |
| Not known yet                                                             | `Unknown — identifying the repository is part of this ticket.`                                                              | `Unknown`                                  |
| The work touches no repository at all (a hosted-tool setting, a document) | `None — this ticket does not change code.`                                                                                  | `None`                                     |

An investigation into a known service uses the first form, even if it may end without a code change.
Never a local filesystem path.

**Summary** — the situation as the user described it: what is happening, or what the work is.
Statements only; questions go in To Investigate and are not repeated here.

**To Investigate** — present when the user raised an open question or named an unknown. Each bullet
is a question. A hunch the user passed along becomes a question followed by its context:
`Is the new rate limiter the cause? Suggested but not yet checked.`

**Done When** — if the user stated a finish line or a decision to reach, that, in one or two
bullets. Otherwise one of:

- To Investigate is present:
  `Findings are recorded on this ticket and follow-up tickets are filed for the work they uncover.`
- To Investigate is absent: `Scope is defined and this ticket is refined or replaced.`

**Notes** — present when the user supplied reference material: a link, a file path, an error
message, a person to talk to. One bullet each, a short label plus the item unaltered:
`Grafana board: https://…`.

**Title** (the Jira summary field) — imperative, under 70 characters: "Investigate overnight retry
queue backups in the crawler".

Summary through Notes together run to about ten lines of content.

### 4. Present and create

Resolve the Account field first. The capitalizable answer is recorded in a Jira field labeled
"Account", which is required on many issue types. Call
`mcp__atlassian__getJiraIssueTypeMetaWithFields` for the project and issue type, find the field
named "Account", and read its allowed values:

- The field exists and one allowed value plainly matches the answer (a capitalizable /
  non-capitalizable pair): use it.
- The field exists and the match is not plain: list the allowed values and ask the user to pick.
- The field does not exist on this issue type: the review block shows `n/a` and nothing is set.

Show the draft, then ask whether anything should change:

```
**Project:** PROJ
**Type:** Task
**Repository:** owner/repo
**Parent:** PROJ-123 | none
**Account:** <allowed value> (capitalizable: yes | no)
**Summary:** <title>

**Description:**
<description>
```

After the user approves, create it with `mcp__atlassian__createJiraIssue`, passing the description
as markdown, the parent epic, when there is one, as the issue's parent, and the Account value
through `additional_fields` under the field's id from the metadata. Report the key and link.

## Common Mistakes

| Mistake                                                                    | Instead                                                                               |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Adding Requirements, Acceptance Criteria, Technical Notes, or Out of Scope | Those belong to `creating-jira-tickets`. This ticket has only the sections in step 3. |
| Reading the codebase to fill in affected files and patterns                | The implementer does that when they pick the ticket up.                               |
| Turning a guess into a statement ("likely caused by the cache")            | Write it as a question under To Investigate.                                          |
| Asking follow-up questions to firm up the scope                            | The scope is unknown; that is why the ticket is simple.                               |
| Dropping the Repository section because the ticket is small                | The header is the one part that is never trimmed.                                     |
| Saying the same thing in Summary and To Investigate                        | Summary states the situation; To Investigate asks the questions.                      |
