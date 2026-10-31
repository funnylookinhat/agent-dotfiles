#!/usr/bin/env bash
# resolve-review-skill.sh — pick the PR-review skill the orchestrators should prompt a worker with.
#
# Usage:
#   resolve-review-skill.sh [<repo-ref>]
#     <repo-ref> = OWNER/REPO | OWNER/REPO#N | https://github.com/OWNER/REPO/pull/N
#                  (omitted → the repo of the current directory via `gh repo view`)
#
# Output: one JSON object:
#   { "skill":   "moz-wide:review-pr" | "reviewing-pr",
#     "command": "/moz-wide:review-pr" | "/reviewing-pr",   # paste straight into the worker prompt
#     "pluginInstalled": bool, "pluginEnabled": bool,
#     "repoOwner": "seomoz", "orgMatches": bool,
#     "reason": "..." }
#
# Rule: prefer moz-wide:review-pr when the plugin is installed AND enabled AND the repo is in the
# org it serves (seomoz); otherwise fall back to the personal reviewing-pr skill.
#
# Overrides (env):
#   REVIEW_SKILL=reviewing-pr|moz-wide:review-pr   force the answer (reason says "forced")
#   REVIEW_ORG=seomoz                              org the plugin skill is allowed to review
#   MOZ_WIDE_PLUGIN_GLOB=<glob to review-pr/SKILL.md>  where to look for the plugin skill
#   CLAUDE_SETTINGS=<path>                         settings.json to read enabledPlugins from
# Requires: gh (authenticated, only when no <repo-ref> is given), jq.
set -euo pipefail

ORG="${REVIEW_ORG:-seomoz}"
GLOB="${MOZ_WIDE_PLUGIN_GLOB:-$HOME/.claude/plugins/cache/ai-foundations/moz-wide/*/skills/review-pr/SKILL.md}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

# --- repo owner -------------------------------------------------------------
ref="${1:-}"
if [[ -z "$ref" ]]; then
  nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
    || { echo "not inside a git repo — pass OWNER/REPO" >&2; exit 1; }
  OWNER="${nwo%%/*}"
elif [[ "$ref" =~ ^https?://github\.com/([^/]+)/ ]]; then
  OWNER="${BASH_REMATCH[1]}"
elif [[ "$ref" =~ ^([^/#]+)/[^/#]+(#[0-9]+)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
else
  echo "unrecognized repo reference: $ref (want OWNER/REPO, OWNER/REPO#N, or a PR URL)" >&2
  exit 1
fi

# --- plugin presence --------------------------------------------------------
INSTALLED=false
# shellcheck disable=SC2086  # the glob must expand
for f in $GLOB; do
  [[ -f "$f" ]] && { INSTALLED=true; break; }
done

ENABLED=false
if [[ -f "$SETTINGS" ]]; then
  if jq -e '.enabledPlugins["moz-wide@ai-foundations"] == true' "$SETTINGS" >/dev/null 2>&1; then
    ENABLED=true
  fi
fi

ORG_MATCHES=false
[[ "$OWNER" == "$ORG" ]] && ORG_MATCHES=true

# --- decide -----------------------------------------------------------------
if [[ -n "${REVIEW_SKILL:-}" ]]; then
  case "$REVIEW_SKILL" in
    reviewing-pr|moz-wide:review-pr) SKILL="$REVIEW_SKILL"; REASON="forced by REVIEW_SKILL" ;;
    *) echo "REVIEW_SKILL must be reviewing-pr or moz-wide:review-pr" >&2; exit 1 ;;
  esac
elif [[ "$INSTALLED" != true ]]; then
  SKILL=reviewing-pr; REASON="moz-wide plugin not installed"
elif [[ "$ENABLED" != true ]]; then
  SKILL=reviewing-pr; REASON="moz-wide plugin installed but not enabled in $SETTINGS"
elif [[ "$ORG_MATCHES" != true ]]; then
  SKILL=reviewing-pr; REASON="repo owner '$OWNER' is not '$ORG'; moz-wide:review-pr declines it"
else
  SKILL=moz-wide:review-pr; REASON="plugin installed and enabled; repo is in $ORG"
fi

jq -n --arg skill "$SKILL" --arg owner "$OWNER" --arg reason "$REASON" \
  --argjson installed "$INSTALLED" --argjson enabled "$ENABLED" --argjson org "$ORG_MATCHES" \
  '{skill:$skill, command:("/"+$skill), pluginInstalled:$installed, pluginEnabled:$enabled,
    repoOwner:$owner, orgMatches:$org, reason:$reason}'
