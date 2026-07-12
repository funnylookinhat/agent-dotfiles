---
name: just-do-it
description:
  Use when the user explicitly asks for a quick, already-specified fix — "just do it", "just fix
  it", "quick change", a one-liner or few-line edit, often after working out the approach with you
  over several messages — and wants it done immediately without brainstorming, planning, debugging
  cycles, or test-first workflows.
---

# Just Do It

## Overview

The user has **explicitly authorized skipping the usual process**. Per using-superpowers, explicit
user instruction overrides skill workflows. So make the change directly and fast.

**Do NOT invoke** brainstorming, writing-plans, systematic-debugging, or test-driven-development for
this task. Do not enter plan mode.

## When to Use

- User says "just do it / just fix it / quick change / one-liner".
- The change is small in _scope_ — a handful of lines, and the intent is settled (either stated now
  or worked out with you earlier in the conversation).

**When NOT to use** (fall back to the normal process): the change isn't actually small, spans many
files, or making it _correctly_ needs a design decision or human judgment you can't infer.

## Use the Conversation as the Spec

The decision you and the user reached across previous messages **IS the spec.** Before touching
anything, ground yourself in what's already been said — the file, the approach, the values, the
tradeoffs you agreed on. Do not re-ask or re-derive what's already settled; acting on the settled
decision is the whole point.

## The Recipe

1. **Read as far as you need to be confident.** Start from the conversation context, then read the
   target code plus whatever related code — callers, imports, types, the actual structure of the
   thing you're changing, similar usages — you need to be _sure_ the change is correct. Trace as
   deep as necessary. Never edit blind. (What you keep small is the _edit_, not your _reading_.)
2. **Make the change** — your best judgment from context + code. If genuinely ambiguous between two
   readings, pick the most likely and make it. Don't stop to ask.
3. **Quick sanity check if fast** — re-read the diff, or typecheck/lint the file. Skip full test
   suites unless the user asked.
4. **Report in 1–2 lines** what you changed. No essays, no skill-triage narration.

## Escape Hatch — STOP the fast path if

- **Being confident would require a human decision**, not just more reading — the correct fix
  depends on a design choice, an ambiguous tradeoff, or intent you can't infer from the conversation
  or the code. Say so and switch to the normal process.
- The scope turns out to be large — many files, architectural change. Switch to the normal process.
- The change is **destructive or irreversible** (data loss, force-push, prod migration, deleting
  things you didn't create) → confirm before acting, regardless of "just do it".

Key distinction: **"not sure yet" is not the escape hatch — it's a signal to read more code.** Only
bail when reading more _can't_ make you sure.

## Red Flags — you're adding ceremony the user rejected

- "Let me write a failing test first" → No. Make the change; verify by sanity check.
- "Let me clarify what they meant" → No, if the answer is in the conversation or discoverable in the
  code. Read, infer, act.
- "I'm not certain, so I'll bail to the escape hatch" → No, if a few more file reads would make you
  certain. Read more, then act.
- "Let me also fix the other places for consistency" → No, unless asked. Investigate widely to
  _understand_; keep the _edit_ to what was specified.
- Writing a paragraph about which skills you did or didn't invoke → No. Just do it, then report in
  1–2 lines.
