#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$HOME/.claude"
DEST="$REPO_DIR/claude"

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

npm --prefix "$REPO_DIR" run format-fix

git -C "$REPO_DIR" add -A
if git -C "$REPO_DIR" diff --cached --quiet; then
  echo "No changes to commit."
else
  git -C "$REPO_DIR" commit -m "Backup claude config $(date +%Y-%m-%d)"
  git -C "$REPO_DIR" push
fi
