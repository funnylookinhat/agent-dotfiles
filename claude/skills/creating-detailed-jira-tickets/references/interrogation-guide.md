# Interrogation Guide

A question bank for grilling the user on a single ticket. **Do not walk the whole list** — pick the
dimensions that are actually live for this ticket, and follow the answers where they lead.

Skip any dimension the codebase already answers. Go read it instead.

---

## Problem and motivation

Use when the ticket arrived as a solution ("add a retry queue") with no stated problem.

- What breaks today, and who notices when it does?
- How often does this happen? Is it getting worse?
- What happens if we simply don't do this?
- Why now rather than next quarter — is something forcing the timing?
- Is there a workaround people use today? What does it cost them?

## Users and triggers

- Who performs this action — end user, admin, internal ops, a background job?
- What are they doing immediately before and after?
- How often: many times a day, or twice a year?
- Is this the first time they encounter this flow, or a repeat interaction?

## Scope boundaries

Always ask at least one of these. Out-of-scope is the section most often missing and most often
needed.

- What is explicitly _not_ part of this ticket?
- What nearby thing will someone be tempted to fix while they're in there — and should they?
- Is there a smaller version that still delivers value? Should that be the ticket instead?
- Does this need to ship as one unit, or can it land in pieces?

## Behavior specifics

The happy path is usually stated. These usually aren't.

- What does the empty state look like — no data, first run, new account?
- What happens on failure? Distinguish: user error, our bug, upstream timeout.
- What exactly does the user see for each failure — inline error, toast, silent retry, nothing?
- Is the operation retryable? Idempotent? What if it runs twice?
- What if two people do this at once?
- What happens to work in progress if it fails halfway?

## Data

- What new data gets stored, and where?
- Does existing data need migrating or backfilling? Can it be done online?
- How long is it retained? Is any of it personal or regulated?
- What is the source of truth if two systems now hold this?

## Limits and edge cases

- What are the size, rate, or count limits? What happens at the limit?
- Who is allowed to do this — any permission or role checks?
- Multi-tenant: can one customer's action affect another's?
- Timezones, locales, currencies — does any of this apply?
- What is the behavior for a very old account, or a brand new one?

## Dependencies and blast radius

- What has to land before this can start?
- What else consumes this code path and might break?
- Does this change an API contract anyone outside the team depends on?
- Does another team need to know, or do anything?

## Done and verifiable

Push until every answer here is binary.

- How does a reviewer verify this works, concretely?
- What would QA click, and what should they see?
- What metric or log would show it working in production?
- What would tell us it's broken after release?

## Rollout

Ask when the change is user-visible, risky, or touches data.

- Feature flag, or ship direct?
- Does anything need to happen in a specific order across services?
- How do we roll back? Is rollback safe after data has been written?
- Does anyone need to be told — support, docs, customers?

---

## Turning vague answers into specific ones

| They said               | Ask                                                                 |
| ----------------------- | ------------------------------------------------------------------- |
| "Handle it gracefully"  | Which failures, and what does the user see for each?                |
| "It should be fast"     | Fast enough that what? Give me a number or a user-visible bar.      |
| "Standard permissions"  | Which roles, specifically? What does a denied user see?             |
| "Like the existing one" | Which one? Should it match exactly, or differ somewhere?            |
| "For now"               | What's the trigger that makes us revisit it — and is that a ticket? |
| "Probably fine"         | If it isn't fine, who finds out and how?                            |
| "Just make it work"     | Name one case where it currently doesn't.                           |

## Accepting non-answers

"I don't know", "you decide", and "doesn't matter" are legitimate answers. Push exactly once with a
narrower question. If it's still open:

- **Deferred decision** → `## Open Questions` in the ticket, phrased as the actual question
- **You picked something** → `## Assumptions` in the ticket, stated plainly so a reader can object

Do not keep asking. Do not silently choose and omit the note.
