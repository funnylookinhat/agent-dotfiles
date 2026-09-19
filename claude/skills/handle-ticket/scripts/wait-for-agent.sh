#!/usr/bin/env bash
# Wait until <agent> finishes its turn, or needs attention.
# Emits exactly one line, then exits — arm with the Monitor tool, persistent: true.
#
# usage: wait-for-agent.sh <agent-name> [poll-seconds]
#   DONE <agent>      turn finished
#   SETTLED <agent>   turn finished but status still says "working" (see below)
#   BLOCKED <agent>   needs input — go look
#   GONE <agent>      no longer resolvable. NOTE: after /finish-worktree this is the
#                     EXPECTED success signal — removing the workspace kills the session
#                     you were waiting on. Confirm with `herdr worktree list`.
#
# WHY THE PANE-QUIESCENCE CHECK EXISTS:
# agent_status is a lifecycle state, not a turn boundary. It stays "working" while
# background shells the session spawned keep running, long after the turn has ended —
# so waiting on status alone (including `herdr agent wait --until idle`) hangs forever
# on a session that is plainly finished. If the tail of the pane stops changing while
# nominally "working", the turn is over and only stray shells remain.
set -u
AGENT="$1"
INT="${2:-120}"
idle=0
seen_working=0
quiet=0
last=""
while true; do
  st=$(herdr agent get "$AGENT" 2>/dev/null | jq -r '.result.agent.agent_status // "gone"')
  cur=$(herdr agent read "$AGENT" --source recent-unwrapped --lines 12 2>/dev/null | md5sum | cut -d' ' -f1)
  case "$st" in
    working)
      seen_working=1
      idle=0
      if [ -n "$last" ] && [ "$cur" = "$last" ]; then
        quiet=$((quiet + 1))
      else
        quiet=0
      fi
      if [ "$quiet" -ge 5 ]; then
        echo "SETTLED $AGENT (pane quiet; background shells still running)"
        exit 0
      fi
      ;;
    idle | done)
      quiet=0
      idle=$((idle + 1))
      # Require having seen it work, so a prompt that has not started yet
      # is not mistaken for a finished turn.
      if [ "$seen_working" = 1 ] && [ "$idle" -ge 2 ]; then
        echo "DONE $AGENT"
        exit 0
      fi
      # Fallback: a whole turn can begin and end between two polls.
      if [ "$idle" -ge 4 ]; then
        echo "DONE $AGENT (never observed working)"
        exit 0
      fi
      ;;
    blocked)
      echo "BLOCKED $AGENT needs input"
      exit 2
      ;;
    gone)
      echo "GONE $AGENT no longer resolvable"
      exit 3
      ;;
    *)
      idle=0
      quiet=0
      ;;
  esac
  last="$cur"
  sleep "$INT"
done
