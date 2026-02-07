#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="https://raw.githubusercontent.com/yidakee/vibe-better-with-claude-code-vbw/main/VERSION"

FILES=(
  "$ROOT/VERSION"
  "$ROOT/.claude-plugin/plugin.json"
  "$ROOT/.claude-plugin/marketplace.json"
  "$ROOT/marketplace.json"
)

LOCAL=$(cat "$ROOT/VERSION" | tr -d '[:space:]')

# Fetch the authoritative version from GitHub
REMOTE=$(curl -sf --max-time 5 "$REPO_URL" 2>/dev/null | tr -d '[:space:]')
if [[ -z "$REMOTE" ]]; then
  echo "Error: Could not fetch version from GitHub." >&2
  exit 1
fi

# Use whichever is higher as the base (protects against local being behind)
BASE="$REMOTE"
if [[ "$(printf '%s\n%s' "$LOCAL" "$REMOTE" | sort -V | tail -1)" == "$LOCAL" ]]; then
  BASE="$LOCAL"
fi

# Auto-increment patch version
MAJOR="${BASE%%.*}"
REST="${BASE#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"
NEW="${MAJOR}.${MINOR}.$((PATCH + 1))"

echo "GitHub version:  $REMOTE"
echo "Local version:   $LOCAL"
echo "Bumping to:      $NEW"
echo ""

# Update all files — bail on first failure
printf '%s\n' "$NEW" > "$ROOT/VERSION"

jq --arg v "$NEW" '.version = $v' "$ROOT/.claude-plugin/plugin.json" > "$ROOT/.claude-plugin/plugin.json.tmp" \
  && mv "$ROOT/.claude-plugin/plugin.json.tmp" "$ROOT/.claude-plugin/plugin.json"

jq --arg v "$NEW" '.plugins[0].version = $v' "$ROOT/.claude-plugin/marketplace.json" > "$ROOT/.claude-plugin/marketplace.json.tmp" \
  && mv "$ROOT/.claude-plugin/marketplace.json.tmp" "$ROOT/.claude-plugin/marketplace.json"

jq --arg v "$NEW" '.plugins[0].version = $v' "$ROOT/marketplace.json" > "$ROOT/marketplace.json.tmp" \
  && mv "$ROOT/marketplace.json.tmp" "$ROOT/marketplace.json"

echo "Updated 4 files:"
for f in "${FILES[@]}"; do
  echo "  ${f#$ROOT/}"
done
echo ""
echo "Version is now $NEW"
