#!/usr/bin/env bash
# resolve-base-branch.sh — pick the branch a new worktree should start from, and bring it
# up to date with origin first.
#
# `herdr worktree create` without --base starts the new branch from the checkout's current
# HEAD — whatever branch happened to be active, however stale. This resolves the repo's
# default branch (or an explicitly requested one), fetches it from origin, fast-forwards
# the local branch when that is safe, and prints the value to pass as `--base`.
#
# Usage:
#   resolve-base-branch.sh --cwd <repo-or-worktree-dir> [--base <ref>]
#     --cwd    any directory inside the checkout (a linked worktree is fine)
#     --base   a branch the ticket or the user explicitly asked for; `origin/` prefix is
#              tolerated. Omit it to use the repository's default branch.
#
# Output: one JSON object; exit 0 only when status is OK.
#   { "status": "OK" | "NOT_FOUND" | "FETCH_FAILED" | "NO_DEFAULT" | "NO_ORIGIN",
#     "branch": "main",                 # the branch chosen
#     "source": "arg" | "default",
#     "onOrigin": true,                 # false when --base names a local-only branch
#     "sha": "<commit>",                # the commit the new branch will start from
#     "base": "main" | "<commit>",      # pass this verbatim as `herdr worktree create --base`
#     "localInSync": true,              # local branch == origin after this ran
#     "localFastForwarded": false,      # this run moved the local branch
#     "checkedOutAt": "/path" | null,   # where the local branch is checked out, if anywhere
#     "reason": "..." }
#   `base` is the branch name when the local branch matches origin, otherwise the fetched
#   commit — never `origin/<branch>`, which would give the new branch an upstream whose name
#   differs from its own and break a plain `git push`.
# Exit 2 when --cwd is not inside a git repository.
# Requires: git, jq.
set -uo pipefail

cwd="$PWD"; want=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)  cwd="$2"; shift 2 ;;
    --base) want="$2"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

emit() { # <status> <exit> [jq --arg k v ...]
  local status="$1" code="$2"; shift 2
  jq -n --arg status "$status" "$@" \
    '{status:$status} + ($ARGS.named | del(.status))
     | (.onOrigin, .localInSync, .localFastForwarded) |= (if . == null then . else . == "true" end)
     | .checkedOutAt |= (if . == "" then null else . end)'
  exit "$code"
}

git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $cwd" >&2; exit 2; }
# The main checkout: branch refs are shared, but fast-forwarding a checked-out branch
# must happen in whichever worktree has it out.
main_wt="$(git -C "$cwd" worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
G=(git -C "$main_wt")

"${G[@]}" remote get-url origin >/dev/null 2>&1 \
  || emit NO_ORIGIN 1 --arg reason "no 'origin' remote in $main_wt; add one or pass --base"

# --- 1. which branch? ------------------------------------------------------------------
source=default
if [[ -n "$want" ]]; then
  branch="${want#refs/heads/}"; branch="${branch#origin/}"; source=arg
else
  branch="$("${G[@]}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch#origin/}"
  if [[ -z "$branch" ]]; then
    # origin/HEAD is only recorded at clone time; ask the remote.
    branch="$("${G[@]}" ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/{sub("refs/heads/","",$2); print $2; exit}')"
    [[ -n "$branch" ]] && "${G[@]}" remote set-head origin "$branch" >/dev/null 2>&1
  fi
  [[ -n "$branch" ]] || emit NO_DEFAULT 1 --arg reason "could not determine origin's default branch (origin/HEAD unset and ls-remote failed); pass --base"
fi

# --- 2. fetch it ---------------------------------------------------------------------
on_origin=true
if ! err="$("${G[@]}" fetch --quiet origin "refs/heads/$branch:refs/remotes/origin/$branch" 2>&1)"; then
  if grep -qiE "couldn't find remote ref|remote ref does not exist|invalid refspec" <<<"$err"; then
    on_origin=false
    "${G[@]}" rev-parse -q --verify "refs/heads/$branch" >/dev/null 2>&1 \
      || emit NOT_FOUND 1 --arg branch "$branch" --arg source "$source" --arg reason "'$branch' exists neither on origin nor locally"
  else
    emit FETCH_FAILED 1 --arg branch "$branch" --arg source "$source" --arg reason "git fetch origin $branch failed: ${err//$'\n'/ }"
  fi
fi

checked_out="$("${G[@]}" worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0=="branch "b{print p; exit}')"

if [[ "$on_origin" == false ]]; then
  sha="$("${G[@]}" rev-parse "refs/heads/$branch")"
  emit OK 0 --arg branch "$branch" --arg source "$source" --arg onOrigin false --arg sha "$sha" --arg base "$branch" \
    --arg localInSync true --arg localFastForwarded false --arg checkedOutAt "$checked_out" \
    --arg reason "'$branch' is not on origin; using the local branch as it is"
fi

# --- 3. bring the local branch up to date when that is a plain fast-forward --------------
sha="$("${G[@]}" rev-parse "refs/remotes/origin/$branch")"
in_sync=false; ff=false; note=""
if local_sha="$("${G[@]}" rev-parse -q --verify "refs/heads/$branch" 2>/dev/null)"; then
  if [[ "$local_sha" == "$sha" ]]; then
    in_sync=true; note="local $branch already matches origin"
  elif ! "${G[@]}" merge-base --is-ancestor "$local_sha" "$sha"; then
    note="local $branch has commits origin does not; left alone"
  elif [[ -z "$checked_out" ]]; then
    "${G[@]}" update-ref "refs/heads/$branch" "$sha" "$local_sha" && { in_sync=true; ff=true; note="fast-forwarded local $branch"; }
  elif [[ -n "$(git -C "$checked_out" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    note="local $branch is checked out at $checked_out with uncommitted changes; left alone"
  elif git -C "$checked_out" merge --ff-only --quiet "$sha" >/dev/null 2>&1; then
    in_sync=true; ff=true; note="fast-forwarded local $branch in $checked_out"
  else
    note="could not fast-forward $branch in $checked_out; left alone"
  fi
elif "${G[@]}" branch --quiet --track "$branch" "refs/remotes/origin/$branch" >/dev/null 2>&1; then
  in_sync=true; ff=true; note="created local $branch tracking origin"
else
  note="no local $branch and could not create one"
fi

base="$sha"; [[ "$in_sync" == true ]] && base="$branch"
emit OK 0 --arg branch "$branch" --arg source "$source" --arg onOrigin true --arg sha "$sha" --arg base "$base" \
  --arg localInSync "$in_sync" --arg localFastForwarded "$ff" --arg checkedOutAt "$checked_out" \
  --arg reason "fetched origin/$branch; $note"
