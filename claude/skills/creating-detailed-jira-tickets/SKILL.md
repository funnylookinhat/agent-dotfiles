---
name: creating-detailed-jira-tickets
description:
  Use ONLY when the user explicitly asks to be interrogated, grilled, questioned at length, or
  pushed hard for details while creating Jira tickets — e.g. "grill me for details", "ask me lots of
  questions about each ticket", "interrogate me", "really detailed tickets". For all ordinary Jira
  ticket creation, use creating-jira-tickets instead.
---

# Creating Detailed Jira Tickets

## Overview

Create Jira tickets by interrogating the user first. The user has explicitly asked to be questioned
— treat unanswered ambiguity as a defect, not as something to paper over with a reasonable-sounding
guess.

Core principle: **every sentence in the ticket traces to something the user said, something you read
in the code, or an assumption you stated out loud and they accepted.**

## When NOT to Use

- The user just wants a ticket → use `creating-jira-tickets`
- The user is in a hurry, said "quick", or gave a complete spec already
- Refining a ticket that already exists → use `refining-jira-tickets`

## The Grilling Cannot Be Delegated

`AskUserQuestion` is blocked inside subagents, and so is every other route to the user:

```
Error: No such tool available: AskUserQuestion. AskUserQuestion is not
available inside subagents.
```

A subagent told to "interview the user" will invent both the questions and the answers, then return
them as if they were real. That produces a confidently-wrong ticket, which is worse than a thin one.

**You ask the questions, in the main conversation.** Subagents are still useful — just not for this.
Dispatch them to read code and find what is ambiguous; ask about it yourself.

## Workflow

### 1. Establish the ticket set

Get the list of tickets before grilling on any of them. Confirm with the user:

- The rough list, one line each
- Whether any should be merged (not atomic) or split (more than one logical change)
- Project key, and parent epic if there is one

Do not proceed until the list is agreed. Interrogating someone about a ticket that gets deleted two
rounds later wastes the exact resource this skill is spending — their attention.

### 2. Recon before you ask

For each ticket, find out what the codebase already answers. Dispatch a subagent per ticket (they
are independent — fan them out in one message) to report:

- Files, modules, and endpoints the work touches
- Existing patterns the work should follow
- Anything that makes the stated intent look wrong or harder than it sounds

**Never ask the user something the code can tell you.** Asking "what's the current timeout?" when
you could have grepped it burns credibility and their patience.

### 3. Interrogate

Work one ticket at a time. Ask **3–6 numbered questions per round**, in prose, so the user can
answer in a single message. Then follow up on whatever came back vague.

Draw questions from `references/interrogation-guide.md` — load it now. Pick the dimensions that are
live for this ticket; do not walk the whole list.

Rules for the round:

- **Follow up on every vague answer.** "Handle errors gracefully" is not an answer. Which errors,
  and what does the user see for each?
- **Ask for the negative space.** What is explicitly out of scope? What should the implementer _not_
  touch?
- **Push once, then accept.** If they say "I don't know" or "you decide", ask one clarifying
  question. If it is still open, stop pushing — record it (step 4) and move on.
- **State assumptions as assumptions.** "I'm assuming this is per-workspace, not global — correct
  me" is a question. Silently writing "per-workspace" into the ticket is not.

### 4. Record what stayed open

Anything unresolved goes into the ticket explicitly, never silently:

- Decisions the user deferred → `## Open Questions` section
- Gaps you filled yourself → `## Assumptions` section, each one stated plainly

A ticket with three honest open questions is more useful than one that reads complete and isn't.

### 5. Draft, confirm, create

Use the templates in `~/.claude/skills/creating-jira-tickets/references/ticket-guide.md` and the
drafting principles in that skill's step 3 — they are shared, not duplicated here. Add the
`Open Questions` and `Assumptions` sections from step 4 above.

Present the draft, ask for changes, then create with `mcp__atlassian__createJiraIssue` after
approval. Report the key and link.

Then move to the next ticket. Carry forward what you learned — do not re-ask questions the previous
ticket already settled.

## When to Stop Grilling

Stop on the ticket when all of these hold:

- Every acceptance criterion is answerable yes or no
- The error and empty cases have stated behavior, or are stated as out of scope
- Out of Scope is non-empty, or the boundary is genuinely unambiguous
- A stranger could implement it without asking the user anything

Stop early, regardless, if the user says to. "That's enough" ends the interrogation for that ticket
— write it up with an `Open Questions` section covering the rest.

## Red Flags

| Thought                                       | Reality                                               |
| --------------------------------------------- | ----------------------------------------------------- |
| "I'll have a subagent interview them"         | Blocked. The subagent will fabricate the answers.     |
| "This one's obvious, I'll skip the questions" | They asked to be grilled on _each_ ticket. Ask.       |
| "I'll fill this gap with a sensible default"  | Fine — but write it in the Assumptions section.       |
| "They seem annoyed, I'll just write it"       | Ask if they want to stop. Don't decide that silently. |
| "I'll ask everything in one giant list"       | 3–6 per round. A 20-question wall gets skimmed.       |
| "I'll ask what file this lives in"            | Go read the code. Only ask what code can't answer.    |
