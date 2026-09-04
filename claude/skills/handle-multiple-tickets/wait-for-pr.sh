#!/usr/bin/env bash
# Wait until <branch> has an open PR, or its agent has gone idle without one.
# Emits exactly one line, then exits — arm with the Monitor tool, persistent: true.
#
# usage: wait-for-pr.sh <branch> <agent-name>
#   PR_OPEN <branch> #<n>   the PR opened; proceed to the review step
#   STALLED <agent>         idle ~15 min with no PR; it is stuck or awaiting input
#
# Run from inside the repo so gh resolves it, or export GH_REPO=owner/name.
set -u
BRANCH="$1"
AGENT="$2"
idle=0
while true; do
  pr=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$pr" ]; then
    echo "PR_OPEN $BRANCH #$pr"
    exit 0
  fi
  st=$(herdr agent get "$AGENT" 2>/dev/null | jq -r '.result.agent.agent_status // "unknown"')
  if [ "$st" = "idle" ]; then
    idle=$((idle + 1))
  else
    idle=0
  fi
  if [ "$idle" -ge 3 ]; then
    echo "STALLED $AGENT is idle with no open PR for $BRANCH"
    exit 1
  fi
  sleep 300
done
