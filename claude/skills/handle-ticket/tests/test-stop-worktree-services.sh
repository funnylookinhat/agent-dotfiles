#!/usr/bin/env bash
# Exercises stop-worktree-services.sh against a fake docker and real throwaway processes.
# Usage: tests/test-stop-worktree-services.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stop-worktree-services.sh"
export PATH="$here/bin:$PATH"
fail=0
check() { # <name> <jq-expr that must be true> <json>
  if jq -e "$2" <<<"$3" >/dev/null; then echo "  ok   $1"; else echo "  FAIL $1 :: $2"; echo "$3" | jq -c . ; fail=1; fi
}

wt="$(mktemp -d)"; wt="$(cd "$wt" && pwd -P)"
elsewhere="$(mktemp -d)"
export DOCKER_LOG="$wt/../docker-$$.log"; : >"$DOCKER_LOG"
cleanup() { kill -KILL "$in1" "$in2" "$out1" "$sh1" "${stubborn:-}" 2>/dev/null; rm -rf "$wt" "$elsewhere" "$DOCKER_LOG"; }
trap cleanup EXIT

# A "server" running from inside the worktree, one in a subdirectory, one outside, and a shell inside.
mkdir -p "$wt/sub"
( cd "$wt"     && exec sleep 1000 ) & in1=$!
( cd "$wt/sub" && exec sleep 1000 ) & in2=$!
( cd "$elsewhere" && exec sleep 1000 ) & out1=$!
mkfifo "$elsewhere/fifo"
# an interactive-looking shell with no children: it idles on a fifo nobody writes to
( cd "$wt" && exec bash -c 'trap : TERM; exec 9<>"$1"; while :; do read -t 5 -u 9 _; done' _ "$elsewhere/fifo" ) & sh1=$!
disown -a
sleep 0.3

echo "dry run: reports, touches nothing"
out="$(DOCKER_FIXTURE_IDS=$'aaa\nbbb' DOCKER_FIXTURE_PROJECT=flh-x DOCKER_FIXTURE_CONFIG="$wt/docker-compose.yml,$wt/docker-compose.override.yml" \
  "$S" "$wt" --dry-run)"
check dryRun        '.dryRun == true' "$out"
check worktree      ".worktree == \"$wt\"" "$out"
check composeProj   '.compose | length == 1 and .[0].project == "flh-x" and .[0].action == "would-down"' "$out"
check composeFiles  '.compose[0].configFiles | length == 2' "$out"
check composeIds    '.compose[0].containers == ["aaa","bbb"]' "$out"
check procsFound    "[.processes[].pid] | sort == ([$in1,$in2] | sort)" "$out"
check procsAction   '[.processes[].action] | all(. == "would-term")' "$out"
check outsideKept   "[.processes[].pid] | index($out1) == null" "$out"
check shellSkipped  "(.skipped | map(select(.pid == $sh1))) == [{pid:$sh1, comm:\"bash\", reason:\"interactive\"}]" "$out"
check stillAlive    "[$([[ -d /proc/$in1 ]] && echo true || echo false), $([[ -d /proc/$in2 ]] && echo true || echo false)] | all" "$out"
check noDown        "$(grep -c ' down ' "$DOCKER_LOG") == 0" "$out"

echo "real run with compose plugin: down by project, kills strays, keeps the shell"
: >"$DOCKER_LOG"
out="$(DOCKER_FIXTURE_IDS=$'aaa\nbbb' DOCKER_FIXTURE_PROJECT=flh-x DOCKER_FIXTURE_CONFIG="$wt/docker-compose.yml" "$S" "$wt")"
check composeDown   '.compose[0].action == "down"' "$out"
downline="$(grep ' down ' "$DOCKER_LOG" || true)"
check downArgs      "\"$downline\" | test(\"^docker compose -p flh-x -f $wt/docker-compose.yml --project-directory $wt down --remove-orphans\$\")" "$out"
check termed        '[.processes[].action] | all(. == "term")' "$out"
sleep 0.3
check in1Dead       "$([[ -d /proc/$in1 ]] && echo false || echo true)" "$out"
check in2Dead       "$([[ -d /proc/$in2 ]] && echo false || echo true)" "$out"
check out1Alive     "$([[ -d /proc/$out1 ]] && echo true || echo false)" "$out"
check sh1Alive      "$([[ -d /proc/$sh1 ]] && echo true || echo false)" "$out"

echo "no plugin, standalone docker-compose absent, down fails: falls back to stop/rm"
: >"$DOCKER_LOG"
out="$(PATH="$here/bin:/usr/bin:/bin" DOCKER_FIXTURE_NO_PLUGIN=1 DOCKER_FIXTURE_IDS='ccc' DOCKER_FIXTURE_PROJECT=p2 DOCKER_FIXTURE_CONFIG="$wt/docker-compose.yml" "$S" "$wt")"
check fallback      '.compose[0].action == "stop-rm"' "$out"
check stopLogged    "$(grep -c '^docker stop ccc$' "$DOCKER_LOG") == 1" "$out"
check rmLogged      "$(grep -c '^docker rm ccc$' "$DOCKER_LOG") == 1" "$out"

echo "nothing running: empty arrays, exit 0"
out="$("$S" "$wt")"; code=$?
check exit0         "$code == 0" "$out"
check empty         '.compose == [] and .processes == []' "$out"

echo "a SIGTERM-ignoring process is escalated to kill"
( cd "$wt" && exec perl -e '$SIG{TERM}="IGNORE"; sleep 1000' ) & stubborn=$!
disown -a
sleep 0.3
out="$("$S" "$wt")"
check escalated     "[.processes[] | select(.pid == $stubborn) | .action] == [\"kill\"]" "$out"
sleep 0.3
check stubbornDead  "$([[ -d /proc/$stubborn ]] && echo false || echo true)" "$out"

echo "bad path: exit 2"
"$S" "$wt/does-not-exist" >/dev/null 2>&1; code=$?
[[ $code -eq 2 ]] && echo "  ok   bad path (exit 2)" || { echo "  FAIL bad path :: exit $code"; fail=1; }

[[ $fail -eq 0 ]] && echo "stop-worktree-services: all passed" || { echo "stop-worktree-services: FAILURES"; exit 1; }
