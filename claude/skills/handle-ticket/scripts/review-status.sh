#!/usr/bin/env bash
# review-status.sh — report what the last skill-driven review of a PR did, for EITHER review engine.
#
# Usage:
#   review-status.sh <pr>
#     <pr> = https://github.com/OWNER/REPO/pull/N | OWNER/REPO#N | N (bare number → current repo)
#
# Output: one JSON object:
#   {
#     "owner","repo","pr",
#     "headSha":      "<full sha>",  "state": "open"|"closed",  "draft": bool, "merged": bool,
#     "engine":       "moz-wide:review-pr" | "reviewing-pr" | null,   # which skill left the newest marker
#     "reviewed":     bool,          # any marker at all
#     "reviewedSha":  "<sha>"|null,  # sha named by the newest marker
#     "reviewedAt":   "<iso>"|null,
#     "upToDate":     bool,          # reviewedSha == headSha  → nothing new for a reviewer to look at
#     "inline":       n,             # inline findings the newest review posted (0 ⇒ nothing to handle)
#     "blocking": n, "nit": n, "preExisting": n,   # by severity tag; all 0 for reviewing-pr
#     "heading":      {blocking,nit,preExisting}|null,  # counts the moz review body *claims* (may differ from inline if comments were deleted)
#     "handlingRepliesSince": bool   # a SKILL:Handling-PR-Comments reply was posted after reviewedAt
#   }
#
# Markers recognised:
#   moz-wide:review-pr  — a PR *review* whose body carries `<!-- moz-review:v1 sha=<head> -->`;
#                         its inline findings are the comments attached to that review. Fallback
#                         posting (`posting: comments`) puts the same marker on an issue comment and
#                         bare `<!-- moz-review:v1 -->` markers on standalone inline comments.
#   reviewing-pr        — an issue comment carrying `<!-- reviewing-pr:sha=<head> -->`; its inline
#                         findings are top-level review comments prefixed `SKILL:Reviewing-PR`.
# When both engines have reviewed, the newest marker wins.
# Requires: gh (authenticated), jq.
set -euo pipefail

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

base="repos/$OWNER/$REPO"
pr_json="$(gh api "$base/pulls/$PR")"
reviews="$(gh api --paginate "$base/pulls/$PR/reviews" | jq -s 'add // []')"
issue_comments="$(gh api --paginate "$base/issues/$PR/comments" | jq -s 'add // []')"
review_comments="$(gh api --paginate "$base/pulls/$PR/comments" | jq -s 'add // []')"

# Newest marker across both engines, as {engine, sha, at, reviewId|null}.
marker="$(jq -n \
  --argjson reviews "$reviews" --argjson issues "$issue_comments" '
  def moz_sha: capture("<!-- moz-review:v1 sha=(?<s>[0-9a-fA-F]{7,40})") | .s;
  def legacy_sha: capture("<!-- reviewing-pr:sha=(?<s>[0-9a-fA-F]{7,40})") | .s;
  [ ($reviews[] | select(.body != null and (.body | test("<!-- moz-review:v1 sha=")))
      | {engine:"moz-wide:review-pr", sha:(.body|moz_sha), at:.submitted_at, reviewId:.id, body:.body}),
    ($issues[] | select(.body != null and (.body | test("<!-- moz-review:v1 sha=")))
      | {engine:"moz-wide:review-pr", sha:(.body|moz_sha), at:.created_at, reviewId:null, body:.body}),
    ($issues[] | select(.body != null and (.body | test("<!-- reviewing-pr:sha=")))
      | {engine:"reviewing-pr", sha:(.body|legacy_sha), at:.created_at, reviewId:null, body:.body})
  ] | sort_by(.at) | last // null')"

if [[ "$marker" == "null" ]]; then
  ENGINE=null; REVIEWED=false; SHA=""; AT=""; REVIEW_ID=null; HEADING=null
  inline_json='[]'
else
  ENGINE="$(jq -r '.engine' <<<"$marker")"
  REVIEWED=true
  SHA="$(jq -r '.sha' <<<"$marker")"
  AT="$(jq -r '.at' <<<"$marker")"
  REVIEW_ID="$(jq -r '.reviewId // "null"' <<<"$marker")"
  HEADING="$(jq '.body
    | capture("### Review: (?<b>[0-9]+) blocking, (?<n>[0-9]+) nit, (?<p>[0-9]+) pre-existing")
    | {blocking:(.b|tonumber), nit:(.n|tonumber), preExisting:(.p|tonumber)}' <<<"$marker" 2>/dev/null || echo null)"
  [[ -z "$HEADING" ]] && HEADING=null

  if [[ "$ENGINE" == "moz-wide:review-pr" && "$REVIEW_ID" != "null" ]]; then
    # Findings are the comments attached to that review — exact, no time-window heuristics.
    inline_json="$(gh api --paginate "$base/pulls/$PR/reviews/$REVIEW_ID/comments" | jq -s 'add // []')"
  elif [[ "$ENGINE" == "moz-wide:review-pr" ]]; then
    # Fallback posting: standalone inline comments carrying the bare marker, posted at/after the body.
    inline_json="$(jq --arg at "$AT" '[ .[] | select(.in_reply_to_id == null)
      | select(.body != null and (.body | test("<!-- moz-review:v1 -->")))
      | select(.created_at >= $at) ]' <<<"$review_comments")"
  else
    inline_json="$(jq --arg at "$AT" '[ .[] | select(.in_reply_to_id == null)
      | select(.body != null and (.body | startswith("SKILL:Reviewing-PR")))
      | select(.created_at >= $at) ]' <<<"$review_comments")"
  fi
fi

HANDLING_SINCE="$(jq --arg at "$AT" --arg pfx "$HANDLING_PREFIX" '
  [ .[] | select(.body != null and (.body | startswith($pfx)))
        | select($at == "" or (.created_at > $at)) ] | length > 0' <<<"$review_comments")"

jq -n \
  --arg owner "$OWNER" --arg repo "$REPO" --argjson pr "$PR" \
  --argjson prj "$pr_json" --argjson reviewed "$REVIEWED" \
  --argjson engine "$( [[ "$ENGINE" == null ]] && echo null || jq -n --arg e "$ENGINE" '$e')" \
  --arg sha "$SHA" --arg at "$AT" --argjson heading "$HEADING" \
  --argjson inline "$inline_json" --argjson handling "$HANDLING_SINCE" '
  def sev($tag): [ $inline[] | select(.body | test("\\*\\*\\[review-pr: " + $tag + "\\]\\*\\*")) ] | length;
  { owner:$owner, repo:$repo, pr:$pr,
    headSha:$prj.head.sha, state:$prj.state, draft:$prj.draft, merged:($prj.merged // false),
    engine:$engine, reviewed:$reviewed,
    reviewedSha:(if $sha=="" then null else $sha end),
    reviewedAt:(if $at=="" then null else $at end),
    upToDate:($reviewed and $sha == $prj.head.sha),
    inline:($inline|length),
    blocking:sev("blocking"), nit:sev("nit"), preExisting:sev("pre-existing"),
    heading:$heading,
    handlingRepliesSince:$handling }'
