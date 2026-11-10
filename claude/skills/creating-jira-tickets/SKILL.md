---
name: creating-jira-tickets
description:
  Use when creating a Jira ticket to plan upcoming work. Prompts for project key, issue type,
  repository, optional parent epic, and capitalizability, then drafts and creates the ticket via the
  Atlassian MCP tool.
---

# Creating Jira Tickets

## Overview

Draft well-structured Jira tickets that are clear for human readers and useful for AI agents picking
up the work. Gather context, draft the ticket for review, then create it in Jira.

## Workflow

### 1. Gather Context

Before drafting, collect the information needed:

- Read the user's description of the work to be done
- Check CLAUDE.md for project key, issue types, and conventions — use any found values as defaults,
  but do not assume they exist
- Always ask the user to confirm or provide:
  - **Project key** (e.g. `ENG`, `PLAT`)
  - **Issue type** (Epic, Story, Task, or Bug)
  - **Repository** — the GitHub `owner/repo` the work lands in. Resolve a candidate first (step 2)
    and present it for confirmation; do not ask cold.
  - **Parent epic** (optional — ticket key or title; skip if not applicable)
  - **Capitalizable** — whether this work is capitalizable for accounting purposes (yes/no). The
    answer sets the ticket's "Account" field (step 5).
  - **What are we doing and why?** (optional — why this work matters, what it means for the
    business, and how it helps users; skip if not provided)
- Review relevant code, designs, or prior tickets if referenced

### 2. Resolve the Repository

Every ticket names the GitHub repository the work lands in, as `owner/repo`. An agent that picks the
ticket up later starts from that name — not from whatever directory it happens to be launched in —
so a ticket without it leaves the agent guessing which codebase to open.

Find the candidate, in this order, and stop at the first that answers:

1. The user named a repository.
2. The description names code — a service, file, endpoint, or module. Find which local checkout
   contains it: checkouts live at `~/source/github.com/<owner>/<repo>/`, so
   `ls ~/source/github.com/*/` for a service name, or `grep -rl` a file or symbol across the
   candidates. Exclude `node_modules`, `.git`, and env/config files (`config/env`, `*.env`) from
   that grep — they hold live credentials, and a match there is noise.
3. The current working directory is inside a git checkout: `git remote get-url origin` names it.
   Treat this as a default to confirm, not an answer — the user may be filing a ticket for a
   different service from the one they are sitting in.
4. None of the above: list the plausible repositories from `ls ~/source/github.com/*/` and ask the
   user to pick.

Then verify the candidate exists with `gh repo view <owner/repo> --json name` and confirm it with
the user alongside the other step-1 answers. A repository that is still uncertain when you reach the
draft is a question for the user now, not a hedge in the ticket.

Work that needs changes in two repositories is two tickets (see Atomic scope below). An Epic lists
every repository its child tickets touch.

### 3. Determine Issue Type

Select the appropriate type based on the work described:

| Type  | When to use                                              |
| ----- | -------------------------------------------------------- |
| Epic  | High-level goal grouping multiple related stories/tasks  |
| Story | User-facing functionality with clear "who/what/why"      |
| Task  | Technical work, infrastructure, or internal improvements |
| Bug   | Something is broken and needs fixing                     |

### 4. Draft the Ticket

Write the ticket using the description template from `references/ticket-guide.md`. Load the
reference file to get the appropriate template for the issue type.

If the user provided a "What are we doing and why?" answer in step 1, add it as its own section
titled `## What are we doing and why?` at the very top of the description, above the type-specific
template. It is separate from the template's own Context/Goal section — do not merge the two. If the
user did not provide it, omit the section entirely; do not invent one.

Always add the `## Repository` section from the guide, directly below "What are we doing and why?"
(or at the very top when that section is absent), using the repository confirmed in step 2. It is
required for every issue type; the guide covers the Epic and no-code-change forms.

**Key principles to follow while drafting:**

- **Self-contained** — Include all context needed to do the work. Inline relevant details rather
  than linking to external documents without summary.
- **Imperative titles** — Start with a verb: "Add session timeout handling", not "Session timeout
  handling" or "We need to add session timeout handling".
- **Outcome over implementation** — Describe what the system should do, not how to code it. "Display
  inline error on invalid credentials" not "Add a toast component to the error handler".
- **Binary acceptance criteria** — Each criterion must be answerable yes or no. "Page loads in under
  2 seconds" not "Performance is acceptable".
- **Explicit scope** — State what is out of scope when there is ambiguity. Humans infer scope from
  organizational context; future readers and AI agents do not.
- **Technical context inline** — Mention affected files, modules, endpoints, and patterns directly
  in the description, as paths relative to the ticket's repository root. This helps both developers
  and AI agents orient quickly.
- **Atomic scope** — One logical change per ticket, in one repository. If the work has independent
  parts, or needs changes in more than one repository, suggest separate tickets.

### 5. Present for Review

Resolve the Account field first. The capitalizable answer is recorded in a Jira field labeled
"Account", which is required on many issue types. Call
`mcp__atlassian__getJiraIssueTypeMetaWithFields` for the project and issue type, find the field
named "Account", and read its allowed values:

- The field exists and one allowed value plainly matches the answer (a capitalizable /
  non-capitalizable pair): use it.
- The field exists and the match is not plain: list the allowed values and ask the user to pick.
- The field does not exist on this issue type: the review block shows `n/a` and nothing is set.

Show the drafted ticket to the user in a clear format:

```
**Project:** PROJ
**Type:** Epic/Story/Task/Bug
**Repository:** owner/repo
**Account:** <allowed value> (capitalizable: yes | no)
**Summary:** <title>

**Description:**
<full description content>
```

Ask if any changes are needed before creating.

### 6. Create in Jira

After the user approves the draft, create the ticket using `mcp__atlassian__createJiraIssue`,
passing the Account value from step 5 through `additional_fields` under the field's id from the
metadata. Report back with the ticket key and link.

## Resources

### references/

- `ticket-guide.md` — Description templates for each issue type and acceptance criteria format
  guidance. Load this file when drafting a ticket.
