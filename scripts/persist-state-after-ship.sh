#!/usr/bin/env bash
set -euo pipefail

# persist-state-after-ship.sh — Extract project-level sections from archived
# STATE.md and write a fresh root STATE.md so todos, decisions, skills, blockers,
# and codebase profile survive across milestone boundaries.
#
# Usage: persist-state-after-ship.sh ARCHIVED_STATE_PATH OUTPUT_PATH PROJECT_NAME
#
# Called by Ship mode (vibe.md Step 5) AFTER moving STATE.md to the archive.
# Reads the archived copy and writes a minimal root STATE.md with only
# project-level sections. Milestone-specific sections (Current Phase, Activity
# Log) are excluded — they belong in the archive.
#
# Project-level sections (preserved):
#   ## Decisions (including ### Skills subsection)
#   ## Todos
#   ## Blockers
#   ## Codebase Profile
#
# Milestone-level sections (excluded):
#   ## Current Phase / ## Phase Status
#   ## Activity Log / ## Recent Activity
#
# Exit codes:
#   0 = success
#   1 = archived STATE.md not found or args missing

if [[ $# -lt 3 ]]; then
  echo "Usage: persist-state-after-ship.sh ARCHIVED_STATE_PATH OUTPUT_PATH PROJECT_NAME" >&2
  exit 1
fi

ARCHIVED_PATH="$1"
OUTPUT_PATH="$2"
PROJECT_NAME="$3"

if [[ ! -f "$ARCHIVED_PATH" ]]; then
  echo "ERROR: Archived STATE.md not found: $ARCHIVED_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

# Sections to preserve (project-level, survive across milestones)
# Uses awk to extract each section by ## heading, stopping at the next ## heading.
# Handles trailing whitespace on headings and only extracts the first occurrence.
extract_section() {
  local file="$1"
  local heading="$2"
  awk -v h="$heading" '
    BEGIN { pat = "^## " h "[[:space:]]*$" }
    $0 ~ pat && !done { found=1; print; next }
    found && /^## / { found=0; done=1 }
    found { print }
  ' "$file"
}

# Decisions section may use "## Decisions" (template) or "## Key Decisions"
# (bootstrap-state.sh). Handle both, including ### Skills subsection.
extract_decisions_with_skills() {
  local file="$1"
  awk '
    /^## (Key )?Decisions[[:space:]]*$/ && !done { found=1; print; next }
    found && /^## / { found=0; done=1 }
    found { print }
  ' "$file"
}

generate_root_state() {
  echo "# State"
  echo ""
  echo "**Project:** ${PROJECT_NAME}"
  echo ""

  # Decisions (+ Skills subsection)
  local decisions
  decisions=$(extract_decisions_with_skills "$ARCHIVED_PATH")
  if [[ -n "$decisions" ]]; then
    echo "$decisions"
    echo ""
  else
    echo "## Decisions"
    echo "- _(No decisions yet)_"
    echo ""
  fi

  # Todos
  local todos
  todos=$(extract_section "$ARCHIVED_PATH" "Todos")
  if [[ -n "$todos" ]]; then
    echo "$todos"
    echo ""
  else
    echo "## Todos"
    echo "None."
    echo ""
  fi

  # Blockers
  local blockers
  blockers=$(extract_section "$ARCHIVED_PATH" "Blockers")
  if [[ -n "$blockers" ]]; then
    echo "$blockers"
    echo ""
  else
    echo "## Blockers"
    echo "None"
    echo ""
  fi

  # Codebase Profile (optional — only if it exists in archived state)
  local codebase
  codebase=$(extract_section "$ARCHIVED_PATH" "Codebase Profile")
  if [[ -n "$codebase" ]]; then
    echo "$codebase"
    echo ""
  fi
}

generate_root_state > "$OUTPUT_PATH"

exit 0
