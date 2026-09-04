#!/usr/bin/env bash
# Wait until no `build` shard check on <pr> is pending, then print every shard result.
# Emits exactly one line, then exits — arm with the Monitor tool, persistent: true.
#
# usage: wait-for-shards.sh <pr-number>
#   build (22, 0)=pass build (22, 1)=fail ...
#
# Use after re-running failed shards, so you confirm the rerun rather than predicting it.
# Adjust the "build" prefix to match this repo's shard check names.
set -u
PR="$1"
while true; do
  s=$(gh pr checks "$PR" --json name,bucket 2>/dev/null)
  if [ -n "$s" ]; then
    pend=$(printf '%s' "$s" | jq -r '[.[] | select(.name | startswith("build")) | select(.bucket == "pending")] | length' 2>/dev/null)
    if [ "$pend" = "0" ]; then
      printf '%s' "$s" | jq -r '[.[] | select(.name | startswith("build")) | "\(.name)=\(.bucket)"] | join(" ")'
      exit 0
    fi
  fi
  sleep 120
done
