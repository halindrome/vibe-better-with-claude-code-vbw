#!/usr/bin/env bash
# clean-stale-teams.sh — Clean stale agent team directories
#
# Scans ~/.claude/teams/ for directories with inboxes older than 2 hours.
# Removes stale teams atomically (mv to temp, then rm).
# Called from session-start.sh to prevent state pollution from dead sessions.

set -euo pipefail

# Resolve CLAUDE_DIR
. "$(dirname "$0")/resolve-claude-dir.sh"

TEAMS_DIR="$CLAUDE_DIR/teams"
STALE_THRESHOLD_SECONDS=7200  # 2 hours

# Graceful exit if teams directory doesn't exist
if [ ! -d "$TEAMS_DIR" ]; then
  exit 0
fi

# Temporary directory for atomic cleanup
TEMP_DIR="/tmp/vbw-stale-teams-$$"
mkdir -p "$TEMP_DIR"

# Platform-specific stat command for modification time
get_mtime() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$file" 2>/dev/null || echo "0"
  else
    stat -c %Y "$file" 2>/dev/null || echo "0"
  fi
}

# Current timestamp
NOW=$(date +%s)

# Scan teams directory
for team_dir in "$TEAMS_DIR"/*; do
  [ ! -d "$team_dir" ] && continue

  team_name=$(basename "$team_dir")
  inbox_dir="$team_dir/inboxes"

  # Skip if no inboxes directory
  [ ! -d "$inbox_dir" ] && continue

  # Get most recent file in inboxes
  inbox_mtime=0
  for inbox_file in "$inbox_dir"/*; do
    [ ! -e "$inbox_file" ] && continue
    file_mtime=$(get_mtime "$inbox_file")
    [ "$file_mtime" -gt "$inbox_mtime" ] && inbox_mtime=$file_mtime
  done

  # Skip if inbox has recent activity
  age=$((NOW - inbox_mtime))
  [ "$age" -lt "$STALE_THRESHOLD_SECONDS" ] && continue

  # Stale team detected — atomic cleanup
  mv "$team_dir" "$TEMP_DIR/$team_name" 2>/dev/null || true
done

# Remove temp directory
rm -rf "$TEMP_DIR" 2>/dev/null || true

exit 0
