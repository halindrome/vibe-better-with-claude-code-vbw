#!/usr/bin/env bash
set -euo pipefail

# bootstrap-state.sh — Generate STATE.md for a VBW project
#
# Usage: bootstrap-state.sh OUTPUT_PATH PROJECT_NAME MILESTONE_NAME PHASE_COUNT
#   OUTPUT_PATH      Path to write STATE.md
#   PROJECT_NAME     Name of the project
#   MILESTONE_NAME   Name of the current milestone
#   PHASE_COUNT      Number of phases in the roadmap

if [[ $# -lt 4 ]]; then
  echo "Usage: bootstrap-state.sh OUTPUT_PATH PROJECT_NAME MILESTONE_NAME PHASE_COUNT" >&2
  exit 1
fi

OUTPUT_PATH="$1"
PROJECT_NAME="$2"
MILESTONE_NAME="$3"
PHASE_COUNT="$4"

STARTED=$(date +%Y-%m-%d)

# Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Preserve existing project-level sections if output file already exists
# (e.g., carried forward from a prior milestone by persist-state-after-ship.sh)
EXISTING_TODOS=""
EXISTING_DECISIONS=""
if [[ -f "$OUTPUT_PATH" ]]; then
  EXISTING_TODOS=$(awk '
    { low = tolower($0) }
    low ~ /^##[[:space:]]+todos[[:space:]]*$/ { found=1; next }
    found && /^## / { found=0 }
    found { print }
  ' "$OUTPUT_PATH")
  EXISTING_DECISIONS=$(awk '
    { low = tolower($0) }
    low ~ /^##[[:space:]]+(key )?decisions[[:space:]]*$/ { found=1; next }
    found && /^## / { found=0 }
    found { print }
  ' "$OUTPUT_PATH")
fi

{
  echo "# VBW State"
  echo ""
  echo "**Project:** ${PROJECT_NAME}"
  echo "**Milestone:** ${MILESTONE_NAME}"
  echo "**Current Phase:** Phase 1"
  echo "**Status:** Pending planning"
  echo "**Started:** ${STARTED}"
  echo "**Progress:** 0%"
  echo ""
  echo "## Phase Status"

  for i in $(seq 1 "$PHASE_COUNT"); do
    if [[ "$i" -eq 1 ]]; then
      echo "- **Phase ${i}:** Pending planning"
    else
      echo "- **Phase ${i}:** Pending"
    fi
  done

  echo ""
  echo "## Key Decisions"
  if [[ -n "$EXISTING_DECISIONS" ]]; then
    echo "$EXISTING_DECISIONS"
  else
    echo "| Decision | Date | Rationale |"
    echo "|----------|------|-----------|"
    echo "| _(No decisions yet)_ | | |"
  fi
  echo ""
  echo "## Todos"
  if [[ -n "$EXISTING_TODOS" ]]; then
    echo "$EXISTING_TODOS"
  else
    echo "None."
  fi
  echo ""
  echo "## Recent Activity"
  echo "- ${STARTED}: Created ${MILESTONE_NAME} milestone (${PHASE_COUNT} phases)"
} > "$OUTPUT_PATH"

exit 0
