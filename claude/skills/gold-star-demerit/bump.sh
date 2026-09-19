#!/usr/bin/env bash
# Gold star / demerit tally. Prints the finished report line on stdout.
#   bump.sh gold_stars  -> increment stars, print star report
#   bump.sh demerits    -> increment demerits, print demerit report
#   bump.sh             -> print score report, no write
set -euo pipefail

FILE="${GOLD_STAR_SCORE_FILE:-$HOME/.claude/gold-star-score.json}"
FIELD="${1-}"

case "$FIELD" in
  gold_stars|demerits|"") ;;
  *) echo "usage: $(basename "$0") [gold_stars|demerits]" >&2; exit 2 ;;
esac

if [[ -f "$FILE" ]]; then
  # Fail loudly on a corrupt file rather than silently resetting the tally to 0.
  jq -e 'has("gold_stars") and has("demerits")' "$FILE" >/dev/null 2>&1 || {
    echo "error: $FILE is not a valid score file; refusing to overwrite" >&2; exit 1; }
else
  [[ -n "$FIELD" ]] || { echo "Score: 0 ⭐ / 0 📋 → net: 0"; exit 0; }
  printf '{"gold_stars":0,"demerits":0}\n' > "$FILE"
fi

if [[ -n "$FIELD" ]]; then
  tmp="$(mktemp "${FILE}.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  jq --arg f "$FIELD" '.[$f] += 1' "$FILE" > "$tmp"
  mv "$tmp" "$FILE"
  trap - EXIT
fi

read -r stars demerits < <(jq -r '"\(.gold_stars) \(.demerits)"' "$FILE")
net=$((stars - demerits))

case "$FIELD" in
  gold_stars) echo "⭐ Gold star! Stars: $stars, Demerits: $demerits → net: $net" ;;
  demerits)   echo "📋 Demerit. Stars: $stars, Demerits: $demerits → net: $net" ;;
  *)          echo "Score: $stars ⭐ / $demerits 📋 → net: $net" ;;
esac
