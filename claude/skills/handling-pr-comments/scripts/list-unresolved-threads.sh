#!/usr/bin/env bash
# list-unresolved-threads.sh — print the UNRESOLVED review threads on a GitHub PR as JSON.
#
# Usage:
#   list-unresolved-threads.sh <pr>
#     <pr> = a PR URL (https://github.com/OWNER/REPO/pull/N)
#          | OWNER/REPO#N
#          | N            (bare number — uses the repo in the current directory)
#
# Output: a JSON array to stdout, one object per unresolved thread:
#   {
#     "threadId":  "PRRT_...",        # GraphQL node id (for resolveReviewThread, if ever needed)
#     "anchorId":  123456,            # FIRST comment's databaseId — the reply target
#     "path":      "src/foo.py",
#     "line":      88,                # may be null on outdated threads
#     "isOutdated": false,
#     "comments": [ { "author","createdAt","databaseId","body","diffHunk" }, ... ]  # full thread, in order
#   }
#
# Resolution state lives ONLY in the GraphQL reviewThreads API; this filters isResolved==false.
# isOutdated is reported but NOT treated as resolved — an outdated thread can still be open.
# Requires: gh (authenticated), jq.
set -euo pipefail

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

# --paginate follows reviewThreads pages automatically: the query declares
# $endCursor:String and gh feeds pageInfo.endCursor back in on each request, emitting
# one raw response object per page. We do NOT use gh's --jq (it prints text that leaves
# newlines/tabs in diffHunk/body unescaped, which breaks a downstream parse); instead a
# single `jq -s` slurps all page responses and reshapes across them.
gh api graphql --paginate \
  -f owner="$OWNER" -f name="$REPO" -F pr="$PR" \
  -f query='
query($owner:String!, $name:String!, $pr:Int!, $endCursor:String) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$pr) {
      reviewThreads(first:100, after:$endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path line
          comments(first:100) {
            nodes { databaseId author { login } body createdAt diffHunk }
          }
        }
      }
    }
  }
}' \
  | jq -s '[ .[].data.repository.pullRequest.reviewThreads.nodes[]
             | select(.isResolved == false)
             | { threadId:   .id,
                 anchorId:   (.comments.nodes[0].databaseId),
                 path:       .path,
                 line:       .line,
                 isOutdated: .isOutdated,
                 comments:   [ .comments.nodes[]
                               | { author: (.author.login // "ghost"),
                                   createdAt: .createdAt,
                                   databaseId: .databaseId,
                                   body: .body,
                                   diffHunk: .diffHunk } ] } ]'
