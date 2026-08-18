---
name: start-worktree
description:
  Use when the user invokes /start-worktree with a task prompt, or asks to spin up a new git
  worktree with a Claude session already working on something. Requires a Herdr-managed pane
  (HERDR_ENV=1) and a git repository.
---

# Start Worktree

Create a Herdr worktree for the current repo, start `claude` in its default pane, and hand it the
task — three commands, no discovery needed.

**Arguments:** everything after the invocation is the prompt for the new Claude session. If it's
empty, ask what the session should work on before creating anything.

## Preconditions

- `test "${HERDR_ENV:-}" = 1` — if not, say you're not inside Herdr and stop.
- `git -C "$PWD" rev-parse --show-toplevel` succeeds — if not, ask which repo to use.

## Recipe

1. **Pick names.** Branch: `flh/<kebab-summary>` derived from the task prompt (or
   `flh/<ticket>-<desc>` if a ticket is mentioned; use the user's branch name verbatim if they gave
   one). Agent name: a short unique slug matching `[a-z][a-z0-9_-]{0,31}` (the branch summary
   without the `flh/` prefix works; on a `name already in use` error, check `herdr agent list` and
   pick another).

2. **Create the worktree.** Herdr owns worktree lifecycle — never `git worktree add`:

   ```bash
   herdr worktree create --cwd "$PWD" --branch flh/<name> --no-focus
   ```

   Pass `--base <ref>` only if the user named a base. From the JSON response, capture
   `.result.root_pane.pane_id`, `.result.workspace.workspace_id`, and the checkout path
   (`.result.worktree.path`).

3. **Start claude in the new pane** (the root pane is already an available shell — do not split or
   create panes):

   ```bash
   herdr agent start <agent-name> --kind claude --pane <root-pane-id>
   ```

   This blocks until Claude is ready for input (30s default timeout).

4. **Send the prompt, fire-and-forget** — no `--wait`; the point is a background session, not
   babysitting it:

   ```bash
   herdr agent prompt <agent-name> '<task prompt>'
   ```

   Single-quote the prompt (or pass it via `"$(cat <<'EOF' ... EOF)"` if it contains single quotes)
   so shell interpolation can't mangle it. The response reflects state at send time and may still
   say `idle` — that's normal; don't poll for `working`.

5. **Report back:** branch, checkout path, workspace ID, agent name, and how to check on it
   (`herdr agent get <agent-name>`, or focus the workspace).

Keep the user's focus where it is: `--no-focus` on create, no `agent focus` — unless the user asked
to switch to it.

## Quick reference

| Need                       | Command                                                                        |
| -------------------------- | ------------------------------------------------------------------------------ |
| New pane's ID              | `.result.root_pane.pane_id` from `worktree create` output                      |
| Check on the session later | `herdr agent get <name>` / `herdr agent read <name> --source recent-unwrapped` |
| Tear it down               | `herdr worktree list --cwd "$PWD"` → `herdr worktree remove --workspace <id>`  |

## Common mistakes

- Running `herdr worktree`/`herdr agent` bare to re-read help — the recipe above is current; skip
  discovery.
- `git worktree add` under HERDR_ENV=1 — creates a checkout Herdr doesn't track.
- `agent prompt --wait` — blocks your session on the other agent's whole turn.
- Guessing pane IDs or reusing IDs from examples — always parse the create response.
