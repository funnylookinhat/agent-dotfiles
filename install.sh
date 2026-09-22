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
fi

# MCP servers live in ~/.claude.json, not ~/.claude/settings.json, so they are
# restored through the CLI rather than copied into place.
MCP_SERVERS="$REPO_DIR/claude-json/mcp-servers.json"

if [[ -f "$MCP_SERVERS" ]]; then
  mcp_names=$(jq -r '.mcpServers // {} | keys[]' "$MCP_SERVERS")
  if [[ -n "$mcp_names" ]]; then
    echo "Installing MCP servers..."
    existing_mcps=$(claude mcp list 2>/dev/null || true)
    while IFS= read -r name; do
      if echo "$existing_mcps" | grep -q "^${name}:"; then
        echo "  $name already configured, skipping"
        continue
      fi

      transport=$(jq -r --arg n "$name" '.mcpServers[$n].type // ""' "$MCP_SERVERS")
      url=$(jq -r --arg n "$name" '.mcpServers[$n].url // ""' "$MCP_SERVERS")

      if [[ -z "$url" ]]; then
        echo "  $name has no url (local server?), skipping - add it manually"
        continue
      fi

      echo "  claude mcp add --scope user --transport $transport $name $url"
      claude mcp add --scope user --transport "$transport" "$name" "$url"
    done <<< "$mcp_names"
  fi
fi
