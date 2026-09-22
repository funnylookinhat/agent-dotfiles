#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$HOME/.claude"
DEST="$REPO_DIR/claude"
CLAUDE_JSON="$HOME/.claude.json"

current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" != "main" ]]; then
  read -r -p "Current branch is '$current_branch', not 'main'. Switch to main? [y/N] " answer
  case "$answer" in
    [Yy] | [Yy][Ee][Ss])
      git -C "$REPO_DIR" checkout main
      ;;
    *)
      echo "Aborting backup."
      exit 1
      ;;
  esac
fi

cp "$SOURCE/settings.json" "$DEST/settings.json"
cp -r "$SOURCE/skills/." "$DEST/skills/"

if [[ -f "$SOURCE/gold-star-score.md" ]]; then
  cp "$SOURCE/gold-star-score.md" "$DEST/gold-star-score.md"
fi

if [[ -d "$SOURCE/git-safe" ]]; then
  mkdir -p "$DEST/git-safe"
  cp -r "$SOURCE/git-safe/." "$DEST/git-safe/"
fi

echo "Backed up claude config from $SOURCE"

# ~/.claude.json holds MCP server config alongside machine identity, account
# details, per-project session state and server caches. Extract only the
# mcpServers key so none of the rest can ever land in the repo.
if [[ -f "$CLAUDE_JSON" ]]; then
  mkdir -p "$REPO_DIR/claude-json"
  jq -S '{mcpServers: (.mcpServers // {})}' "$CLAUDE_JSON" > "$REPO_DIR/claude-json/mcp-servers.json"
  echo "Backed up MCP servers from $CLAUDE_JSON"
fi

npm --prefix "$REPO_DIR" run format-fix

git -C "$REPO_DIR" add -A
if git -C "$REPO_DIR" diff --cached --quiet; then
  echo "No changes to commit."
else
  git -C "$REPO_DIR" commit -m "Backup claude config $(date +%Y-%m-%d)"
  git -C "$REPO_DIR" push
fi
