#!/usr/bin/env bash
set -euo pipefail

# migrate-orphaned-state.sh — Recover root STATE.md for brownfield installations
# that shipped a milestone before this fix was deployed.
#
# Usage: migrate-orphaned-state.sh PLANNING_DIR
#
# Called by session-start.sh during startup. Detects the orphaned state:
#   - .vbw-planning/ exists
#   - No root STATE.md
#   - No ACTIVE file (milestone is fully shipped)
#   - At least one milestones/*/STATE.md exists
#
# When detected, calls persist-state-after-ship.sh on the latest archived
# STATE.md to reconstruct a root STATE.md with project-level sections.
#
# Idempotent: no-ops if root STATE.md already exists or ACTIVE is set.
#
# Exit codes: always 0 (fail-open for session-start)

PLANNING_DIR="${1:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Guard: directory must exist
if [[ ! -d "$PLANNING_DIR" ]]; then
  exit 0
fi

# Guard: if root STATE.md exists, nothing to do
if [[ -f "$PLANNING_DIR/STATE.md" ]]; then
  exit 0
fi

# Guard: if ACTIVE file exists, the milestone is live — don't create root state
if [[ -f "$PLANNING_DIR/ACTIVE" ]]; then
  exit 0
fi

# Find the latest archived STATE.md by modification time
latest_state=""
latest_mtime=-1
for f in "$PLANNING_DIR"/milestones/*/STATE.md; do
  [ -f "$f" ] || continue
  mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [[ "$mtime" -gt "$latest_mtime" ]]; then
    latest_mtime="$mtime"
    latest_state="$f"
  fi
done

if [[ -z "$latest_state" ]]; then
  exit 0
fi

# Extract project name from the archived STATE.md
project_name=$(grep -m1 '^\*\*Project:\*\*' "$latest_state" 2>/dev/null | sed 's/\*\*Project:\*\* *//' || echo "Unknown")

# Use persist-state-after-ship.sh to create the root STATE.md
bash "$SCRIPT_DIR/persist-state-after-ship.sh" \
  "$latest_state" "$PLANNING_DIR/STATE.md" "$project_name" 2>/dev/null || true

exit 0
