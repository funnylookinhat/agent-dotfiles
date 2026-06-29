#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$REPO_DIR/claude"
DEST="$HOME/.claude"

if [[ -d "$DEST" ]] && [[ -n "$(ls -A "$DEST" 2>/dev/null)" ]]; then
  read -r -p "This will overwrite existing files in $DEST. Continue? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

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

  mcp_names=$(jq -r '.mcpServers // {} | keys[]' "$SETTINGS")
  if [[ -n "$mcp_names" ]]; then
    echo "Installing MCP servers..."
    existing_mcps=$(claude mcp list 2>/dev/null || true)
    while IFS= read -r name; do
      if echo "$existing_mcps" | grep -q "^${name}:"; then
        echo "  $name already configured, skipping"
      else
        transport=$(jq -r ".mcpServers[\"$name\"].type" "$SETTINGS")
        url=$(jq -r ".mcpServers[\"$name\"].url" "$SETTINGS")
        echo "  claude mcp add --scope user --transport $transport $name $url"
        claude mcp add --scope user --transport "$transport" "$name" "$url"
      fi
    done <<< "$mcp_names"
  fi
fi
