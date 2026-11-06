#!/usr/bin/env bash
# resolve-ticket-repo.sh — find the local checkout a Jira ticket's work belongs in.
#
# Tickets created by creating-jira-tickets carry a "Repository" section naming the GitHub
# OWNER/REPO. This maps that to a checkout under $SOURCE_ROOT/github.com/, so the orchestrators
# can be launched from any directory. The current directory is only a fallback.
#
# Usage:
#   resolve-ticket-repo.sh <ticket-text-file | -> [--cwd <dir>] [--repo OWNER/REPO]
#     <file>   the brief / ticket description (markdown, Jira wiki, or plain text); `-` = stdin
#     --cwd    directory to fall back to when the ticket names no repository (default: $PWD)
#     --repo   skip parsing and resolve this OWNER/REPO (the user named it on the command line)
#
# Output: one JSON object; exit 0 only when status is OK.
#   { "status": "OK" | "NONE" | "NOT_FOUND" | "NOT_CLONED",
#     "repo": "seomoz/app-api", "owner": "seomoz", "name": "app-api",
#     "path": "/home/me/source/github.com/seomoz/app-api",   # OK only
#     "expectedPath": "...",                                  # NOT_CLONED only
#     "source": "ticket" | "arg" | "cwd",
#     "alsoListed": ["seomoz/app-pro-ui"],                    # extra repos an Epic lists
#     "reason": "..." }
#   NONE       the ticket says it changes no code — nothing to check out; escalate.
#   NOT_FOUND  no Repository section and --cwd is not inside a git checkout.
#   NOT_CLONED the ticket names a repo that is not checked out; reason carries the clone command.
#
# Env: SOURCE_ROOT (default $HOME/source) — checkouts live at $SOURCE_ROOT/github.com/OWNER/REPO.
# Requires: git, jq.
set -euo pipefail

ROOT="${SOURCE_ROOT:-$HOME/source}/github.com"
file=""; cwd="$PWD"; forced=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)  cwd="$2"; shift 2 ;;
    --repo) forced="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) file="$1"; shift ;;
  esac
done

emit() { # <status> <exit> [jq --arg k v ...]
  local status="$1" code="$2"; shift 2
  jq -n --arg status "$status" "$@" \
    '{status:$status} + ($ARGS.named | del(.status))
     | if .alsoListed? then .alsoListed |= (split("\n") | map(select(length>0))) else . end'
  exit "$code"
}

# --- 1. what does the ticket name? -------------------------------------------
# Extract the Repository section: from a heading line that says "Repository" (markdown `##`,
# Jira wiki `h2.`, or bold `*Repository*`) up to the next heading of any of those forms.
section() {
  awk '
    function is_heading(l) { return l ~ /^[[:space:]]*(#+[[:space:]]*|h[1-6]\.[[:space:]]*|\*+)[^*#]+(\*+)?[[:space:]]*$/ }
    function is_repo_heading(l) { return tolower(l) ~ /^[[:space:]]*(#+[[:space:]]*|h[1-6]\.[[:space:]]*|\*+)[[:space:]]*repository(\*+)?[[:space:]]*:?[[:space:]]*$/ }
    { if (is_repo_heading($0)) { on=1; next }
      if (on && is_heading($0)) exit
      if (on) print }
  '
}
# Pull every OWNER/REPO out of a block of text: GitHub URLs first, then `owner/repo` tokens.
repos_in() {
  grep -oE 'github\.com[/:][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' <<<"$1" | sed -E 's#^github\.com[/:]##; s#\.git$##' || true
  grep -oE '(^|[^A-Za-z0-9_./-])[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' <<<"$1" | sed -E 's#^[^A-Za-z0-9_.-]##; s#\.git$##' \
    | grep -vE '^(https?|path|lib|src|app|config|test|tests)/' || true
}

repo=""; source=""; also=""
if [[ -n "$forced" ]]; then
  repo="$forced"; source=arg
else
  [[ -n "$file" ]] || { echo "usage: $0 <ticket-file|-> [--cwd DIR] [--repo OWNER/REPO]" >&2; exit 2; }
  text="$(cat "${file/#-/\/dev\/stdin}")"
  sec="$(section <<<"$text")"
  if [[ -n "$sec" ]]; then
    if grep -qiE '^[[:space:]]*[-*]?[[:space:]]*`?none`?([[:space:]]|$|—|-)' <<<"$sec"; then
      emit NONE 1 --arg source ticket --arg reason "ticket says it changes no code: $(head -1 <<<"$sec" | sed 's/^[[:space:]]*//')"
    fi
    # unique, in order of appearance
    mapfile -t found < <(repos_in "$sec" | awk '!seen[$0]++')
    if [[ ${#found[@]} -gt 0 ]]; then
      repo="${found[0]}"; source=ticket
      also="$(printf '%s\n' "${found[@]:1}")"
    fi
  fi
fi

# --- 2. nothing named → the current directory, if it is a checkout ------------------
if [[ -z "$repo" ]]; then
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$top" ]]; then
    emit NOT_FOUND 1 --arg reason "ticket has no Repository section and $cwd is not inside a git checkout; pass --repo OWNER/REPO or add the section to the ticket"
  fi
  url="$(git -C "$top" remote get-url origin 2>/dev/null || true)"
  if [[ "$url" =~ github\.com[/:]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then
    repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
  else
    emit NOT_FOUND 1 --arg reason "ticket has no Repository section and $top has no GitHub origin remote"
  fi
  emit OK 0 --arg repo "$repo" --arg owner "${repo%%/*}" --arg name "${repo##*/}" --arg path "$top" --arg source cwd \
    --arg reason "no Repository section in the ticket; using the checkout at $cwd"
fi

owner="${repo%%/*}"; name="${repo##*/}"

# --- 3. map OWNER/REPO to a checkout ----------------------------------------------
origin_matches() { # <dir> — true when its origin remote points at $repo
  local u; u="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
  [[ "$u" =~ github\.com[/:]${owner}/${name}(\.git)?$ ]]
}
expected="$ROOT/$owner/$name"
path=""
if [[ -d "$expected/.git" || -f "$expected/.git" ]] && origin_matches "$expected"; then
  path="$expected"
else
  # the checkout may sit under a different directory name — find it by origin
  for d in "$ROOT"/*/*/; do
    d="${d%/}"
    [[ -e "$d/.git" ]] || continue
    if origin_matches "$d"; then path="$d"; break; fi
  done
fi

if [[ -z "$path" ]]; then
  emit NOT_CLONED 1 --arg repo "$repo" --arg owner "$owner" --arg name "$name" --arg source "$source" \
    --arg expectedPath "$expected" --arg alsoListed "$also" \
    --arg reason "no checkout of $repo under $ROOT; clone it first: git clone git@github.com:$repo.git $expected"
fi

emit OK 0 --arg repo "$repo" --arg owner "$owner" --arg name "$name" --arg path "$path" --arg source "$source" \
  --arg alsoListed "$also" --arg reason "$( [[ "$path" == "$expected" ]] && echo "checkout at the expected path" || echo "checkout found by origin remote at $path" )"
