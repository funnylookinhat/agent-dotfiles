#!/usr/bin/env bash
# stop-worktree-services.sh — free the memory a finished run left behind. Downs the
# worktree's Docker Compose project(s) and kills stray processes still running from
# inside the worktree (dev servers, watchers, orphaned test runners). The worktree
# itself is untouched: nothing here is `git worktree remove`.
#
# usage: stop-worktree-services.sh <worktree-path> [--dry-run]
#
# Output: one JSON object —
#   {
#     "worktree": "<abs path>", "dryRun": bool,
#     "compose":   [ { "project", "configFiles": [...], "containers": [ids],
#                      "action": "down" | "stop-rm" | "would-down" | "failed" } ],
#     "processes": [ { "pid", "comm", "cmdline", "action": "term" | "kill" | "would-term" } ],
#     "skipped":   [ { "pid", "comm", "reason" } ]      # in the worktree, deliberately left alone
#   }
#
# Containers are found by their compose `working_dir` label, so a project started with
# `--project-directory` elsewhere is not seen — read `compose` to know what was swept.
# Processes are found by cwd under the worktree. Never killed: this script's own
# ancestry (the coordinator's shell and claude), interactive shells, claude, herdr,
# editors, pagers. Those are reported under `skipped` so a live pane is visible.
# Requires: jq, docker (optional — no docker, no compose sweep).
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $(basename "$0") <worktree-path> [--dry-run]" >&2
  exit 2
fi
RAW="$1"; shift
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
WT="$(cd "$RAW" 2>/dev/null && pwd -P)" || { echo "not a directory: $RAW" >&2; exit 2; }

# Leave the worktree so our own children do not count as "running from inside it".
cd /

# Processes we never kill, by comm. Shells and claude are what a Herdr pane is made of;
# the rest are things a human may have open in the worktree.
KEEP_COMM=" zsh bash sh dash fish claude herdr nvim vim vi nano less tmux code node_console "

# ---------- Docker Compose ----------
compose_json='[]'
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    compose_cmd=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose_cmd=(docker-compose)
  else
    compose_cmd=()
  fi
  ids="$(docker ps -aq --filter "label=com.docker.compose.project.working_dir=$WT" 2>/dev/null || true)"
  if [[ -n "$ids" ]]; then
    # project<TAB>config_files<TAB>id, one per container
    rows="$(for id in $ids; do
      docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}	{{index .Config.Labels "com.docker.compose.project.config_files"}}	{{.Id}}' "$id" 2>/dev/null
    done)"
    while IFS= read -r project; do
      [[ -n "$project" ]] || continue
      cfg="$(awk -F'\t' -v p="$project" '$1==p{print $2; exit}' <<<"$rows")"
      cids="$(awk -F'\t' -v p="$project" '$1==p{print $3}' <<<"$rows")"
      fargs=()
      IFS=',' read -ra files <<<"$cfg"
      for f in "${files[@]}"; do [[ -n "$f" ]] && fargs+=(-f "$f"); done
      action="would-down"
      if [[ $DRY -eq 0 ]]; then
        if [[ ${#compose_cmd[@]} -gt 0 ]] && \
           "${compose_cmd[@]}" -p "$project" "${fargs[@]}" --project-directory "$WT" down --remove-orphans >/dev/null 2>&1; then
          action="down"
        elif docker stop $cids >/dev/null 2>&1 && docker rm $cids >/dev/null 2>&1; then
          action="stop-rm"
        else
          action="failed"
        fi
      fi
      entry="$(jq -cn --arg p "$project" --arg cfg "$cfg" --arg ids "$cids" --arg a "$action" \
        '{project:$p, configFiles:($cfg|split(",")|map(select(length>0))), containers:($ids|split("\n")|map(select(length>0))), action:$a}')"
      compose_json="$(jq -c --argjson e "$entry" '. + [$e]' <<<"$compose_json")"
    done < <(awk -F'\t' '{print $1}' <<<"$rows" | sort -u)
  fi
fi

# ---------- Stray processes ----------
declare -A ancestry=()
p=$$
while [[ "$p" -gt 1 ]]; do
  ancestry[$p]=1
  p="$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null || echo 1)"
done

procs_json='[]'; skipped_json='[]'
targets=()
for d in /proc/[0-9]*; do
  pid="${d#/proc/}"
  [[ -n "${ancestry[$pid]:-}" ]] && continue
  cwd="$(readlink "$d/cwd" 2>/dev/null)" || continue
  [[ "$cwd" == "$WT" || "$cwd" == "$WT/"* ]] || continue
  comm="$(cat "$d/comm" 2>/dev/null || echo '?')"
  cmdline="$(tr '\0' ' ' <"$d/cmdline" 2>/dev/null | sed 's/ $//' | cut -c1-200)"
  if [[ "$KEEP_COMM" == *" $comm "* ]]; then
    skipped_json="$(jq -c --arg pid "$pid" --arg c "$comm" '. + [{pid:($pid|tonumber), comm:$c, reason:"interactive"}]' <<<"$skipped_json")"
    continue
  fi
  targets+=("$pid")
  action="would-term"
  [[ $DRY -eq 0 ]] && action="term"
  procs_json="$(jq -c --arg pid "$pid" --arg c "$comm" --arg l "$cmdline" --arg a "$action" \
    '. + [{pid:($pid|tonumber), comm:$c, cmdline:$l, action:$a}]' <<<"$procs_json")"
done

if [[ $DRY -eq 0 && ${#targets[@]} -gt 0 ]]; then
  kill -TERM "${targets[@]}" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    alive=0
    for t in "${targets[@]}"; do [[ -d "/proc/$t" ]] && alive=1; done
    [[ $alive -eq 0 ]] && break
    sleep 0.5
  done
  for t in "${targets[@]}"; do
    if [[ -d "/proc/$t" ]]; then
      kill -KILL "$t" 2>/dev/null || true
      procs_json="$(jq -c --arg pid "$t" 'map(if .pid == ($pid|tonumber) then .action = "kill" else . end)' <<<"$procs_json")"
    fi
  done
fi

jq -n --arg wt "$WT" --argjson dry "$([[ $DRY -eq 1 ]] && echo true || echo false)" \
  --argjson c "$compose_json" --argjson p "$procs_json" --argjson s "$skipped_json" \
  '{worktree:$wt, dryRun:$dry, compose:$c, processes:$p, skipped:$s}'
