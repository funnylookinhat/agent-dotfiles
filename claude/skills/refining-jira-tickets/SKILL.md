---
name: refining-jira-tickets
description:
  Use when an existing Jira ticket needs to be reviewed and improved. Fetches the ticket, evaluates
  it against quality standards for structure, clarity, and completeness, drafts improvements, and
  updates the ticket via the Atlassian MCP tool.
---

# Refining Jira Tickets

## Overview

Review an existing Jira ticket and bring it up to a high standard of clarity: well-structured
description, imperative title, binary acceptance criteria, and enough technical context for both
developers and AI agents to pick up the work without extra clarification.

## Workflow

### 1. Identify the Ticket

If the user has not already provided a ticket key:

- Ask: "Which ticket would you like to refine? (provide the ticket key, e.g. `ENG-123`)"

Once you have the key, fetch the ticket using `mcp__atlassian__getJiraIssue`.

### 2. Understand the Ticket

Read the fetched ticket carefully:

- Note the issue type (Epic, Story, Task, Bug)
- Read the current summary and description
- Identify what information is present, vague, or missing
- **Inventory inline images:** List every inline image embedded in the description (Jira markup
  `!filename!` or ADF image nodes). You will need to account for each one in your draft.
- **Inventory attachments:** Note all file attachments on the ticket. These are never removed — do
  not include them in any edit call.

Check CLAUDE.md for project conventions — use any found values as context, but do not assume they
exist.

### 3. Evaluate Against Quality Standards

Assess the ticket against each criterion:

| Criterion                       | What to check                                                              |
| ------------------------------- | -------------------------------------------------------------------------- |
| **Imperative title**            | Starts with a verb ("Add...", "Fix...", "Remove...")                       |
| **Self-contained**              | All context needed to do the work is inline, not just linked               |
| **Outcome over implementation** | Describes what the system does, not how to code it                         |
| **Binary acceptance criteria**  | Each criterion is answerable yes or no                                     |
| **Explicit scope**              | Out-of-scope items stated when there is ambiguity                          |
| **Technical context**           | Affected files, modules, endpoints, or patterns mentioned                  |
| **Atomic scope**                | Covers one logical change; flag if it should be split                      |
| **Correct structure**           | Follows the template for its issue type (see `references/ticket-guide.md`) |

### 4. Draft Improvements

Load `references/ticket-guide.md` for the appropriate issue type template. Rewrite or fill in any
sections that are missing, vague, or poorly structured.

**Key principles while drafting:**

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
  splitting into separate tickets.

Preserve any information from the original that is accurate and well-written. Only replace or expand
what needs improvement.

**Inline image preservation (non-negotiable):** Every inline image inventoried in Step 2 must appear
in the revised description. If a rewritten section no longer provides a natural home for an image,
move it to the end of the description rather than dropping it. Dropping an inline image is never
acceptable, even if you cannot determine its purpose.

**Attachment preservation (non-negotiable):** File attachments are part of the ticket record and
must never be removed. Do not pass an attachments field to the edit call.

### 5. Present for Review

Show the proposed changes to the user, clearly distinguishing what changed:

```
**Ticket:** PROJ-123
**Type:** Epic/Story/Task/Bug

**Summary (updated):** <new title>
  was: <original title>

**Description (updated):**
<full proposed description>
```

If the summary did not change, omit the "was:" line. Call out any sections that are new or
significantly rewritten so the user can evaluate them quickly.

Ask if any changes are needed before updating.

### 6. Update in Jira

After the user approves, update the ticket using `mcp__atlassian__editJiraIssue`. Report back
confirming the ticket key and what was updated.

Before submitting the edit call, verify:

- Every inline image from Step 2 is present in the new description
- The edit call does not include an attachments field

## Resources

### references/

- `ticket-guide.md` — Description templates for each issue type and acceptance criteria format
  guidance. Load this file when drafting refinements.
