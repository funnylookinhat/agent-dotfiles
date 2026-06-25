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
