---
name: creating-jira-tickets
description:
  Use when creating a Jira ticket to plan upcoming work. Prompts for project key, issue type,
  optional parent epic, and capitalizability, then drafts and creates the ticket via the Atlassian
  MCP tool.
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
  - **Parent epic** (optional — ticket key or title; skip if not applicable)
  - **Capitalizable** — whether this work is capitalizable for accounting purposes (yes/no)
  - **What are we doing and why?** (optional — why this work matters, what it means for the
    business, and how it helps users; skip if not provided)
- Review relevant code, designs, or prior tickets if referenced

### 2. Determine Issue Type

Select the appropriate type based on the work described:

| Type  | When to use                                              |
| ----- | -------------------------------------------------------- |
| Epic  | High-level goal grouping multiple related stories/tasks  |
| Story | User-facing functionality with clear "who/what/why"      |
| Task  | Technical work, infrastructure, or internal improvements |
| Bug   | Something is broken and needs fixing                     |

### 3. Draft the Ticket

Write the ticket using the description template from `references/ticket-guide.md`. Load the
reference file to get the appropriate template for the issue type.

If the user provided a "What are we doing and why?" answer in step 1, add it as its own section
titled `## What are we doing and why?` at the very top of the description, above the type-specific
template. It is separate from the template's own Context/Goal section — do not merge the two. If the
user did not provide it, omit the section entirely; do not invent one.

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
  in the description. This helps both developers and AI agents orient quickly.
- **Atomic scope** — One logical change per ticket. If the work has independent parts, suggest
  separate tickets.

### 4. Present for Review

Show the drafted ticket to the user in a clear format:

```
**Project:** PROJ
**Type:** Epic/Story/Task/Bug
**Summary:** <title>

**Description:**
<full description content>
```

Ask if any changes are needed before creating.

### 5. Create in Jira

After the user approves the draft, create the ticket using `mcp__atlassian__createJiraIssue`. Report
back with the ticket key and link.

## Resources

### references/

- `ticket-guide.md` — Description templates for each issue type and acceptance criteria format
  guidance. Load this file when drafting a ticket.
