#!/usr/bin/env bash
# post-review.sh — post a reviewing-pr review to a GitHub PR: one inline comment per finding,
# plus one summary issue comment carrying the last-reviewed-sha marker. In one call.
#
# Usage:
#   post-review.sh [--dry-run] <pr> <sha> <review.json>
#     <pr>          = a PR URL | OWNER/REPO#N | N (bare number → current repo)
#     <sha>         = the head sha being reviewed (inline comments anchor to this commit;
#                     must be a commit in the PR — pass review-state.sh .headSha)
#     <review.json> = { "summary": "<optional text>",
#                       "findings": [ { "path": "...", "line": <int>, "side": "RIGHT"|"LEFT"?, "body": "..." }, ... ] }
#     --dry-run     = print what would be posted; make no API calls
#
# Build review.json with the Write tool (no permission prompt), then run this ONCE.
# Allowlist this single script (e.g. Bash(/abs/path/to/post-review.sh:*)) to avoid per-run prompts.
#
# Every inline body AND the summary is prefixed with `SKILL:Reviewing-PR` + two newlines,
# applied idempotently (won't double-prefix). The summary always posts (even with 0 findings)
# so the sha marker advances for the next incremental review.
# GitHub rejects inline comments on lines not in the PR diff — such findings report FAILED, not fatal.
# Requires: gh (authenticated), jq.
set -euo pipefail

PREFIX=$'SKILL:Reviewing-PR\n\n'

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY=1; shift; fi
if [[ $# -lt 3 ]]; then
  echo "usage: $(basename "$0") [--dry-run] <pr-url|owner/repo#N|N> <sha> <review.json>" >&2
  exit 2
fi
ref="$1"; SHA="$2"; file="$3"
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

jq -e 'has("findings") and (.findings|type=="array")' "$file" >/dev/null 2>&1 \
  || { echo "review.json must be an object with a .findings array" >&2; exit 1; }

prefixed() {  # idempotent prefix
  local body="$1"
  case "$body" in
    "SKILL:Reviewing-PR"*) printf '%s' "$body" ;;
    *) printf '%s' "${PREFIX}${body}" ;;
  esac
}

n="$(jq '.findings | length' "$file")"
echo "posting $n inline comment$([[ "$n" == 1 ]] || echo s) + summary to $OWNER/$REPO#$PR @ ${SHA:0:8}$([[ $DRY == 1 ]] && echo ' (dry-run)' || true)" >&2

err="$(mktemp)"; trap 'rm -f "$err"' EXIT
fail=0
posted=0
for i in $(seq 0 $((n-1))); do
  path="$(jq -r ".findings[$i].path" "$file")"
  line="$(jq -r ".findings[$i].line" "$file")"
  side="$(jq -r ".findings[$i].side // \"RIGHT\"" "$file")"
  body="$(jq -r ".findings[$i].body" "$file")"
  full="$(prefixed "$body")"
  if [[ -z "$path" || "$path" == "null" || -z "$line" || "$line" == "null" ]]; then
    echo "  [$((i+1))/$n] SKIP: finding missing path/line" >&2; fail=1; continue
  fi
  if [[ $DRY == 1 ]]; then
    echo "  [$((i+1))/$n] → $path:$line ($side):" >&2
    printf '%s\n' "$full" | sed 's/^/        /' >&2
    posted=$((posted+1)); continue
  fi
  if url="$(gh api "repos/$OWNER/$REPO/pulls/$PR/comments" \
             -f body="$full" -f commit_id="$SHA" -f path="$path" \
             -F line="$line" -f side="$side" --jq '.html_url' 2>"$err")"; then
    echo "  [$((i+1))/$n] ok  → $url" >&2
    posted=$((posted+1))
  else
    echo "  [$((i+1))/$n] FAILED ($path:$line): $(tr '\n' ' ' <"$err")" >&2
    fail=1
  fi
done

# Summary issue comment — always posted, carries the sha marker for the next incremental run.
summary="$(jq -r '.summary // ""' "$file")"
if [[ -z "$summary" ]]; then
  if [[ "$posted" -eq 0 ]]; then
    summary="Reviewed $OWNER/$REPO@$SHA. No issues found."
  else
    summary="Reviewed $OWNER/$REPO@$SHA. Posted $posted inline comment$([[ "$posted" == 1 ]] || echo s)."
  fi
fi
summary_body="$(printf '%s%s\n\n<!-- reviewing-pr:sha=%s -->' "$PREFIX" "$summary" "$SHA")"

if [[ $DRY == 1 ]]; then
  echo "  → summary issue comment:" >&2
  printf '%s\n' "$summary_body" | sed 's/^/        /' >&2
else
  if surl="$(gh api "repos/$OWNER/$REPO/issues/$PR/comments" -f body="$summary_body" --jq '.html_url' 2>"$err")"; then
    echo "  summary ok → $surl" >&2
  else
    echo "  summary FAILED: $(tr '\n' ' ' <"$err")" >&2
    fail=1
  fi
fi

[[ $fail -eq 0 ]] && echo "done." >&2 || echo "done with errors." >&2
exit $fail
