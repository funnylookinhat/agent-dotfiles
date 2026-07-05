#!/usr/bin/env bash
# post-replies.sh — post threaded replies to review comments on a GitHub PR, in one call.
#
# Usage:
#   post-replies.sh [--dry-run] <pr> <replies.json>
#     <pr>           = a PR URL | OWNER/REPO#N | N (bare number → current repo)
#     <replies.json> = JSON array: [ { "anchorId": <first-comment databaseId>, "body": "<markdown>" }, ... ]
#     --dry-run      = print what would be posted; make no API calls
#
# Build replies.json with the Write tool (no permission prompt), then run this ONCE.
# Allowlist this single script (e.g. Bash(/abs/path/to/post-replies.sh:*)) to avoid
# per-run prompts for reply posting.
#
# anchorId is the thread's FIRST comment databaseId (the `anchorId` field emitted by
# list-unresolved-threads.sh) — replying there threads correctly instead of detaching.
# Requires: gh (authenticated), jq.
set -euo pipefail

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY=1; shift; fi
if [[ $# -lt 2 ]]; then
  echo "usage: $(basename "$0") [--dry-run] <pr-url|owner/repo#N|N> <replies.json>" >&2
  exit 2
fi
ref="$1"; file="$2"
[[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }

if [[ "$ref" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; PR="${BASH_REMATCH[3]}"
elif [[ "$ref" =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]; then
  OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; PR="${BASH_REMATCH[3]}"
elif [[ "$ref" =~ ^[0-9]+$ ]]; then
  PR="$ref"
  nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
    || { echo "not inside a git repo — pass a PR URL or owner/repo#N" >&2; exit 1; }
  OWNER="${nwo%%/*}"; REPO="${nwo##*/}"
else
  echo "unrecognized PR reference: $ref (want a URL, owner/repo#N, or N)" >&2
  exit 1
fi

jq -e 'type=="array" and (length>0) and all(.[]; has("anchorId") and has("body"))' "$file" >/dev/null 2>&1 \
  || { echo "replies.json must be a non-empty array of objects with anchorId and body" >&2; exit 1; }

n="$(jq length "$file")"
echo "posting $n repl$([[ "$n" == 1 ]] && echo y || echo ies) to $OWNER/$REPO#$PR$([[ $DRY == 1 ]] && echo ' (dry-run)' || true)" >&2

err="$(mktemp)"; trap 'rm -f "$err"' EXIT
fail=0
for i in $(seq 0 $((n-1))); do
  anchor="$(jq -r ".[$i].anchorId" "$file")"
  body="$(jq -r ".[$i].body" "$file")"
  if [[ -z "$anchor" || "$anchor" == "null" ]]; then
    echo "  [$((i+1))/$n] SKIP: missing anchorId" >&2; fail=1; continue
  fi
  if [[ $DRY == 1 ]]; then
    echo "  [$((i+1))/$n] → comment $anchor:" >&2
    printf '%s\n' "$body" | sed 's/^/        /' >&2
    continue
  fi
  if url="$(gh api "repos/$OWNER/$REPO/pulls/$PR/comments/$anchor/replies" \
             -f body="$body" --jq '.html_url' 2>"$err")"; then
    echo "  [$((i+1))/$n] ok  → $url" >&2
  else
    echo "  [$((i+1))/$n] FAILED (comment $anchor): $(tr '\n' ' ' <"$err")" >&2
    fail=1
  fi
done

[[ $fail -eq 0 ]] && echo "done." >&2 || echo "done with errors." >&2
exit $fail
