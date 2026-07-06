#!/usr/bin/env bash
# review-state.sh — decide whether reviewing-pr should do a FULL, INCREMENTAL, or NO review.
#
# Usage:
#   review-state.sh <pr>
#     <pr> = a PR URL (https://github.com/OWNER/REPO/pull/N) | OWNER/REPO#N | N (current repo)
#
# Output: a single JSON object to stdout:
#   {
#     "owner","repo","pr",
#     "headSha":        "<full head sha>",
#     "baseRef":        "main",
#     "baseSha":        "<full base sha>",
#     "reviewed":       true|false,               # a prior SKILL:Reviewing-PR summary marker exists
#     "lastReviewedSha":"<sha>"|null,             # sha from the most-recent marker
#     "newCommitsSince": true|false,              # head moved since that marker
#     "handlingRepliesSince": true|false,         # SKILL:Handling-PR-Comments replies after that marker
#     "mode":           "full"|"incremental"|"none"
#   }
#
# The marker is a hidden HTML comment this skill writes on its summary issue comment:
#   <!-- reviewing-pr:sha=<full head sha> -->
# Handling replies are detected by the prefix the handling-pr-comments skill posts with
# (SKILL:Handling-PR-Comments) on PR *review* comments.
# Requires: gh (authenticated), jq.
set -euo pipefail

# The prefix the handling-pr-comments skill stamps its replies with. Override if yours differs.
HANDLING_PREFIX="${HANDLING_PREFIX:-SKILL:Handling-PR-Comments}"

if [[ $# -lt 1 ]]; then
  echo "usage: $(basename "$0") <pr-url | owner/repo#N | N>" >&2
  exit 2
fi

ref="$1"
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

pr_json="$(gh api "repos/$OWNER/$REPO/pulls/$PR")"
HEAD_SHA="$(jq -r '.head.sha' <<<"$pr_json")"
BASE_REF="$(jq -r '.base.ref' <<<"$pr_json")"
BASE_SHA="$(jq -r '.base.sha' <<<"$pr_json")"

# Issue comments carry our summary marker. --paginate emits one array per page; jq -s 'add' merges.
issue_comments="$(gh api --paginate "repos/$OWNER/$REPO/issues/$PR/comments" | jq -s 'add // []')"
last_marker="$(jq '[ .[] | select(.body | test("<!-- reviewing-pr:sha=")) ]
                   | sort_by(.created_at) | last // empty' <<<"$issue_comments")"

if [[ -n "$last_marker" && "$last_marker" != "null" ]]; then
  REVIEWED=true
  LAST_SHA="$(jq -r '.body | capture("<!-- reviewing-pr:sha=(?<s>[0-9a-fA-F]{7,40})") | .s' <<<"$last_marker")"
  LAST_AT="$(jq -r '.created_at' <<<"$last_marker")"
else
  REVIEWED=false; LAST_SHA=""; LAST_AT=""
fi

# Review (inline) comments carry handling-pr-comments replies.
review_comments="$(gh api --paginate "repos/$OWNER/$REPO/pulls/$PR/comments" | jq -s 'add // []')"
HANDLING_SINCE="$(jq --arg at "$LAST_AT" --arg pfx "$HANDLING_PREFIX" '
  [ .[] | select(.body | startswith($pfx))
         | select($at == "" or (.created_at > $at)) ] | length > 0' <<<"$review_comments")"

if [[ "$REVIEWED" == true && -n "$LAST_SHA" && "$LAST_SHA" != "$HEAD_SHA" ]]; then
  NEW_COMMITS=true
else
  NEW_COMMITS=false
fi

# Decide mode.
if [[ "$REVIEWED" != true ]]; then
  MODE=full
elif [[ "$HANDLING_SINCE" == true || "$NEW_COMMITS" == true ]]; then
  MODE=incremental
else
  MODE=none
fi

jq -n \
  --arg owner "$OWNER" --arg repo "$REPO" --argjson pr "$PR" \
  --arg headSha "$HEAD_SHA" --arg baseRef "$BASE_REF" --arg baseSha "$BASE_SHA" \
  --argjson reviewed "$REVIEWED" \
  --arg lastReviewedSha "$LAST_SHA" \
  --argjson newCommitsSince "$NEW_COMMITS" \
  --argjson handlingRepliesSince "$HANDLING_SINCE" \
  --arg mode "$MODE" \
  '{owner:$owner, repo:$repo, pr:$pr,
    headSha:$headSha, baseRef:$baseRef, baseSha:$baseSha,
    reviewed:$reviewed,
    lastReviewedSha:(if $lastReviewedSha=="" then null else $lastReviewedSha end),
    newCommitsSince:$newCommitsSince,
    handlingRepliesSince:$handlingRepliesSince,
    mode:$mode}'
