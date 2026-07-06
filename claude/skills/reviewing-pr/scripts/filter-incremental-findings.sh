#!/usr/bin/env bash
# filter-incremental-findings.sh — keep only findings on lines changed since the last review.
#
# Usage:
#   filter-incremental-findings.sh <fromSha> <toSha> <findings.json>
#     <fromSha> = the last-reviewed sha (review-state.sh .lastReviewedSha)
#     <toSha>   = current head sha (review-state.sh .headSha, usually local HEAD)
#     findings.json = JSON array: [ { "path": "...", "line": <int>, "body": "..." }, ... ]
#
# Prints a filtered JSON array to stdout: only findings whose {path,line} lands on a line
# ADDED or changed on the new side of `git diff fromSha..toSha`. Findings on unchanged lines
# (already-reviewed code, possibly already handled) are dropped. A finding with a null line is
# dropped (nothing to anchor incrementally).
#
# Run from inside the checked-out PR working tree (git diff is local). If <fromSha> is not
# present locally, run `git fetch` first.
# Requires: git, jq.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $(basename "$0") <fromSha> <toSha> <findings.json>" >&2
  exit 2
fi
FROM="$1"; TO="$2"; FILE="$3"
[[ -f "$FILE" ]] || { echo "no such file: $FILE" >&2; exit 1; }

git rev-parse --quiet --verify "$FROM^{commit}" >/dev/null \
  || { echo "commit $FROM not found locally — run 'git fetch' and retry" >&2; exit 1; }

n="$(jq length "$FILE")"
out='[]'
for i in $(seq 0 $((n-1))); do
  path="$(jq -r ".[$i].path" "$FILE")"
  line="$(jq -r ".[$i].line" "$FILE")"
  [[ "$line" == "null" || -z "$line" ]] && continue

  keep=0
  # Parse each hunk header's new-side range: @@ -a,b +c,d @@  (d omitted ⇒ length 1; d==0 ⇒ deletion, skip)
  while IFS= read -r hdr; do
    if [[ "$hdr" =~ \+([0-9]+)(,([0-9]+))? ]]; then
      start="${BASH_REMATCH[1]}"
      len="${BASH_REMATCH[3]:-1}"
      [[ "$len" -eq 0 ]] && continue
      if (( line >= start && line <= start + len - 1 )); then keep=1; break; fi
    fi
  done < <(git diff --unified=0 "$FROM".."$TO" -- "$path" | grep '^@@' || true)

  if [[ "$keep" == 1 ]]; then
    entry="$(jq -c ".[$i]" "$FILE")"
    out="$(jq --argjson e "$entry" '. + [$e]' <<<"$out")"
  fi
done

echo "$out"
