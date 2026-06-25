#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$REPO_DIR/claude"
DEST="$HOME/.claude"

cp -r "$SOURCE/." "$DEST/"

echo "Installed claude config to $DEST"

SETTINGS="$DEST/settings.json"

if [[ -f "$SETTINGS" ]]; then
  plugins=$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$SETTINGS")
  if [[ -n "$plugins" ]]; then
    echo "Installing plugins..."
    while IFS= read -r plugin; do
      echo "  claude plugin install $plugin"
      claude plugin install "$plugin"
    done <<< "$plugins"
  fi
fi
