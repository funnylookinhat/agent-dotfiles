#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$HOME/.claude"
DEST="$REPO_DIR/claude"

cp "$SOURCE/settings.json" "$DEST/settings.json"
cp -r "$SOURCE/skills/." "$DEST/skills/"

if [[ -f "$SOURCE/gold-star-score.md" ]]; then
  cp "$SOURCE/gold-star-score.md" "$DEST/gold-star-score.md"
fi

echo "Imported claude config from $SOURCE"

npm --prefix "$REPO_DIR" run format-fix

SETTINGS="$DEST/settings.json"

if [[ -f "$SETTINGS" ]]; then
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
