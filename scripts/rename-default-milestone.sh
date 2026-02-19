#!/usr/bin/env bash
set -euo pipefail

# rename-default-milestone.sh — Brownfield migration for milestones/default/
#
# Usage: rename-default-milestone.sh PLANNING_DIR
#
# If milestones/default/ exists, derives a meaningful slug from SHIPPED.md
# content (phase names, "What Changed" summary, or phase directory names)
# and renames it. Idempotent — exits 0 if no default/ exists.
#
# Exit codes: 0 on success (including no-op), 1 on failure

PLANNING_DIR="${1:-}"

if [[ -z "$PLANNING_DIR" ]]; then
  echo "Usage: rename-default-milestone.sh PLANNING_DIR" >&2
  exit 1
fi

DEFAULT_DIR="$PLANNING_DIR/milestones/default"

# Idempotent: no default dir → nothing to do
if [[ ! -d "$DEFAULT_DIR" ]]; then
  exit 0
fi

# --- Derive slug from SHIPPED.md ---
derive_slug() {
  local shipped="$DEFAULT_DIR/SHIPPED.md"
  local slug=""

  if [[ -f "$shipped" ]]; then
    # Try 1: Extract phase names from "## Phases" section
    local phases
    phases=$(awk '/^## Phases/ { found=1; next } found && /^## / { exit } found && /^- / { gsub(/^- (Phase [0-9]+: )?/, ""); print }' "$shipped" | head -3)
    if [[ -n "$phases" ]]; then
      # Join phase names with hyphens
      slug=$(echo "$phases" | tr '\n' '-' | sed 's/-$//')
    fi

    # Try 2: Extract from "## What Changed" first line
    if [[ -z "$slug" ]]; then
      local what_changed
      what_changed=$(awk '/^## What Changed/ { found=1; next } found && /^## / { exit } found && /^[^[:space:]]/ { print; exit }' "$shipped")
      if [[ -n "$what_changed" ]]; then
        slug="$what_changed"
      fi
    fi
  fi

  # Try 3: Derive from phase directory names
  if [[ -z "$slug" && -d "$DEFAULT_DIR/phases" ]]; then
    local phase_dirs
    phase_dirs=$(ls -1 "$DEFAULT_DIR/phases/" 2>/dev/null | head -3 | sed 's/^[0-9]*-//')
    if [[ -n "$phase_dirs" ]]; then
      slug=$(echo "$phase_dirs" | tr '\n' '-' | sed 's/-$//')
    fi
  fi

  # Fallback: timestamp-based
  if [[ -z "$slug" ]]; then
    slug="milestone-$(date +%Y%m%d)"
  fi

  # Normalize to kebab-case slug
  echo "$slug" | tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9 -]//g' | \
    sed 's/  */ /g' | \
    tr ' ' '-' | \
    sed 's/--*/-/g' | \
    sed 's/^-//;s/-$//' | \
    head -c 60
}

new_slug=$(derive_slug)

# Guard against empty slug
if [[ -z "$new_slug" ]]; then
  new_slug="milestone-$(date +%Y%m%d)"
fi

new_dir="$PLANNING_DIR/milestones/$new_slug"

# Guard against collision
if [[ -d "$new_dir" ]]; then
  new_dir="${new_dir}-$(date +%H%M%S)"
fi

mv "$DEFAULT_DIR" "$new_dir"

exit 0
