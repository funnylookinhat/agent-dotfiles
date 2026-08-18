---
name: finish-worktree
description:
  Use when the user invokes /finish-worktree, or asks to close/tear down/finish the git worktree the
  current session is working in. Pushes the branch, stops its Docker containers, and removes the
  Herdr workspace. Requires a Herdr-managed pane (HERDR_ENV=1) and a linked worktree.
---

# Finish Worktree

Tear down the Herdr worktree this session is running in: push the branch, stop its Docker
containers, close the workspace. The reverse of `start-worktree`.

**Arguments:** none. The target is always the worktree the session is currently in — never a
worktree named on the command line, and never the main checkout.

**The last step kills the pane you are running in.** `herdr worktree remove` closes the workspace,
which closes this Claude session. Everything else — every check, every push, and the entire report
to the user — must finish before you issue it.

## Preconditions

- `test "${HERDR_ENV:-}" = 1` — if not, say you're not inside Herdr and stop.
- `git -C "$PWD" rev-parse --show-toplevel` succeeds — if not, say you're not in a repo and stop.

## Recipe

1. **Resolve the worktree — and prove it's a linked one.**

   ```bash
   git rev-parse --show-toplevel
   herdr worktree list --cwd "$PWD"
   ```

   From the `.result.worktrees[]` array, pick the entry whose `path` equals the toplevel above.
   Capture its `open_workspace_id`, `path`, and `branch`.

   **That entry MUST have `is_linked_worktree: true`.** If it's `false`, you are in the main
   checkout — say so and stop. Do not remove it. If no entry matches, or the matching entry has no
   `open_workspace_id`, stop and report rather than guessing an ID.

2. **Dirty check — hard stop.**

   ```bash
   git status --porcelain
   ```

   Any output means uncommitted work. Report the files and **stop**. Do not commit, stash, discard,
   stop containers, or remove anything — a worktree that fails this check must be left exactly as it
   was, environment still up. The user decides what to do with the changes.

3. **Push, if there is anything to push.** Find whether the branch has commits the remote doesn't:

   ```bash
   git rev-parse --abbrev-ref --symbolic-full-name '@{u}'
   ```
   - Upstream exists → `git rev-list --count '@{u}..HEAD'`
   - No upstream (command fails) → resolve the default branch with
     `git symbolic-ref --short refs/remotes/origin/HEAD` (fall back to `origin/main`), then
     `git rev-list --count origin/<default>..HEAD`

   Non-zero count → push:

   ```bash
   git push -u origin HEAD
   ```

   Zero commits → say the branch has nothing to push and skip. Never create a PR; that stays an
   explicit, separate action.

   Run each `git` command on its own — never chained with `&&`.

4. **Stop this worktree's Docker containers.** Find them by compose label rather than guessing the
   repo's tooling, using the worktree path from step 1:

   ```bash
   docker ps -aq --filter "label=com.docker.compose.project.working_dir=<worktree-path>"
   ```

   No IDs → nothing to stop, skip silently. Otherwise read each container's project and config
   files:

   ```bash
   docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.project.config_files"}}' <id>
   ```

   For each distinct project, `down` it — `config_files` is comma-separated, so split it into
   repeated `-f` flags:

   ```bash
   docker compose -p <project> -f <file1> [-f <file2>...] --project-directory <worktree-path> down --remove-orphans
   ```

   If `down` fails, fall back to `docker stop <ids>` then `docker rm <ids>` on the IDs you already
   found. Report what you stopped either way.

5. **Report — before removing anything.** Branch and where it now stands (pushed / nothing to push),
   containers stopped, worktree path, and the workspace ID about to close. Once step 6 runs, this
   session is gone and can't tell the user anything.

6. **Remove the worktree.** Herdr owns worktree lifecycle — never `git worktree remove`:
   ```bash
   herdr worktree remove --workspace <open_workspace_id>
   ```
   Add `--force` only if it refuses because the pane has a running process (this session). The
   branch itself is left alone — only the checkout and workspace go away.

## Quick reference

| Need                                  | Command                                                                        |
| ------------------------------------- | ------------------------------------------------------------------------------ |
| This worktree's workspace ID          | `.result.worktrees[] \| select(.path == <toplevel>) \| .open_workspace_id`     |
| Confirm it's safe to remove           | that same entry's `is_linked_worktree` must be `true`                          |
| Containers belonging to this worktree | `docker ps -aq --filter "label=com.docker.compose.project.working_dir=<path>"` |
| Started this worktree                 | `start-worktree` skill                                                         |

## Common mistakes

- **Removing the workspace before reporting.** The remove closes your pane mid-sentence; the user
  never sees what happened.
- **Skipping the `is_linked_worktree` check.** `worktree list` includes the main checkout as the
  first entry — matching on path alone, or trusting `$HERDR_WORKSPACE_ID` blindly, can tear down the
  primary repo.
- **`git worktree remove` under HERDR_ENV=1** — leaves Herdr holding a workspace for a checkout
  that's gone.
- **Doing teardown work before the dirty check.** A run that stops on uncommitted changes must leave
  containers up and nothing pushed.
- **Auto-committing or stashing to get past a dirty tree.** Report and stop; it's the user's call.
- **Assuming the container sweep is exhaustive.** It finds containers whose compose _working dir_ is
  this worktree. One started with `--project-directory` pointing elsewhere won't match — which is
  why step 4 reports what it stopped, so a miss is visible.
