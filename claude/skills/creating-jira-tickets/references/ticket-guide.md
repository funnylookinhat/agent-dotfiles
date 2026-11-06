# Jira Ticket Description Templates

## Optional: What are we doing and why?

When the user provides business rationale — why this work matters, what it means for the business,
or how it helps users — place it in its own section at the very top of the description, above the
type-specific template:

```
## What are we doing and why?
<business rationale: why now, business impact, user benefit>
```

Include this section only when the user provides that rationale. Skip it otherwise — do not invent
content, and do not fold it into the template's own Context/Goal section below.

## Required: Repository

Every ticket names the GitHub repository the work lands in. Place this section directly below "What
are we doing and why?" when that section exists, otherwise at the very top of the description —
always above the type-specific template:

```
## Repository
`<owner>/<repo>` — https://github.com/<owner>/<repo>

All work for this ticket lands in this repository. File paths in this ticket are relative to its root.
```

Rules:

- Use the `owner/repo` form plus the GitHub URL. Never a local filesystem path — the ticket is read
  on other machines and by other people.
- A Story, Task, or Bug names exactly one repository. Work that needs changes in two repositories is
  two tickets.
- An Epic lists one line per repository its child tickets touch, primary first, each with a few
  words on what lands there.
- A ticket that changes no code (a research spike, a document, a configuration change in a hosted
  tool) still has the section, written as `None — this ticket does not change code`, so a reader
  knows the repository was considered rather than forgotten.
- No hedging. "Probably `owner/repo`" or "confirm before starting" turns the section into a question
  the implementer cannot answer. Resolve it before drafting (see the skill's Resolve the Repository
  step).

## Epic

```
## Goal
What outcome this epic achieves and why it matters. One to three sentences.

## Scope
- Key capabilities or changes included
- Grouped by theme if the epic spans multiple areas

## Success Criteria
- High-level, measurable outcomes (not task-level acceptance criteria)
- e.g., "Users can complete checkout without leaving the app"

## Out of Scope
- What is explicitly excluded from this epic

## Technical Notes
- Architectural considerations or constraints
- Cross-cutting concerns (migrations, API versioning, etc.)
```

## Story

```
## Context
Why this work matters and what problem it solves for users.

## Requirements
As a [user type], I want [capability] so that [benefit].

- Requirement 1
- Requirement 2

## Acceptance Criteria
- Criterion 1 (binary, testable)
- Criterion 2
- Criterion 3

## Technical Notes
- Affected modules/files: `path/to/module`
- Related API endpoints: `POST /api/resource`
- Patterns to follow: reference existing implementation in `path/to/example`
- Data model changes: describe schema additions if any

## Out of Scope
- What this ticket intentionally does not cover
```

## Task

```
## Context
Why this work is needed and what was wrong or missing before.

## Requirements
- What specifically needs to happen
- Concrete deliverables

## Acceptance Criteria
- Criterion 1
- Criterion 2

## Technical Notes
- Affected modules/files: `path/to/module`
- Dependencies or prerequisites
- Migration or deployment considerations
```

## Bug

```
## Summary
One-sentence description of the defect.

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen.

## Actual Behavior
What happens instead. Include error messages, screenshots, or logs.

## Environment
- Browser/OS/version if relevant
- Environment: staging/production
- Frequency: always/intermittent

## Acceptance Criteria
- The described scenario produces the expected behavior
- No regression in related functionality

## Technical Notes
- Suspected root cause if known
- Affected code: `path/to/file:line`
- Related logs or error traces
```

---

## Acceptance Criteria Formats

Use a **bulleted list** for most tickets — it is concise and easy to scan:

```
- User sees confirmation toast after saving
- Form validates email format before submission
- API returns 404 for nonexistent resources
```

Use **Given-When-Then** for complex behavioral scenarios where preconditions matter:

```
Given the user has an expired session
When they submit the form
Then they are redirected to login with their form data preserved
```

### Writing Good Criteria

- **Binary**: Answerable as yes or no. Not "performance is acceptable" — instead "page loads in
  under 2 seconds on 3G".
- **Outcome-focused**: Describe what the system does, not how it is implemented.
- **Independent**: Each criterion is testable on its own.
- **Complete**: Cover happy path, error cases, and edge cases. Omit criteria that are obvious or
  universal (e.g., "the app does not crash").

---

## Section Guidance

Not every section is required for every ticket. Omit sections that would just say "N/A". The minimum
viable ticket has:

1. A clear imperative title
2. Repository (where)
3. Context (why)
4. Requirements or reproduction steps (what)
5. At least one acceptance criterion (done when)

Add Technical Notes when the work touches specific code paths, APIs, or data models. Add Out of
Scope when there is genuine ambiguity about boundaries.
