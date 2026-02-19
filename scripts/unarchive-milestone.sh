#!/usr/bin/env bash
set -euo pipefail

# unarchive-milestone.sh — Restore an archived milestone to active work
#
# Usage: unarchive-milestone.sh MILESTONE_DIR PLANNING_DIR
#
# Moves phases/, ROADMAP.md, STATE.md back to root PLANNING_DIR.
# Merges Todos and Decisions sections from both root and archived STATE.md,
# deduplicating by normalized text comparison.
# Deletes SHIPPED.md and removes the milestone dir if empty.
#
# Exit codes: 0 on success, 1 on failure

MILESTONE_DIR="${1:-}"
PLANNING_DIR="${2:-}"

if [[ -z "$MILESTONE_DIR" || -z "$PLANNING_DIR" ]]; then
  echo "Usage: unarchive-milestone.sh MILESTONE_DIR PLANNING_DIR" >&2
  exit 1
fi

if [[ ! -d "$MILESTONE_DIR" ]]; then
  echo "Error: milestone directory not found: $MILESTONE_DIR" >&2
  exit 1
fi

# --- Extract section items from STATE.md ---
# Usage: extract_section_items FILE SECTION_HEADER
# Returns one item per line (list items "- " and table rows "| ")
extract_section_items() {
  local file="$1" header="$2"
  [ -f "$file" ] || return 0
  awk -v hdr="$header" '
    $0 == hdr { found=1; next }
    found && /^## / { exit }
    found && /^- / { print }
    found && /^\| / && !/^\| *[-:]/ && !/^\| *Decision/ { print }
  ' "$file"
}

# --- Normalize a line for dedup comparison ---
# Strips leading "- ", "| ", priority tags, date tags, table cell delimiters, and extra whitespace
normalize_item() {
  echo "$1" | sed 's/^- //' | sed 's/^| //' | sed 's/ |$//g' | sed 's/ | / /g' | \
    sed 's/^\[[^]]*\] //' | \
    sed 's/ *(added [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\})$//' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]'
}

# --- Merge two sets of items with dedup ---
# Usage: merge_items "items1_multiline" "items2_multiline"
# Returns deduplicated union
merge_items() {
  local items1="$1" items2="$2"
  local -a seen_normalized=()
  local -a result=()

  # Process items1 first (keep original formatting)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" == "None." ]] && continue
    local norm
    norm=$(normalize_item "$line")
    [ -z "$norm" ] && continue

    local found=false
    for s in "${seen_normalized[@]+"${seen_normalized[@]}"}"; do
      if [[ "$s" == "$norm" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == false ]]; then
      seen_normalized+=("$norm")
      result+=("$line")
    fi
  done <<< "$items1"

  # Process items2 (add only unseen)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" == "None." ]] && continue
    local norm
    norm=$(normalize_item "$line")
    [ -z "$norm" ] && continue

    local found=false
    for s in "${seen_normalized[@]+"${seen_normalized[@]}"}"; do
      if [[ "$s" == "$norm" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == false ]]; then
      seen_normalized+=("$norm")
      result+=("$line")
    fi
  done <<< "$items2"

  for item in "${result[@]+"${result[@]}"}"; do
    echo "$item"
  done
}

# --- Replace a section in a file with new content ---
# Usage: replace_section FILE SECTION_HEADER NEW_CONTENT
replace_section() {
  local file="$1" header="$2" new_content="$3"
  local tmp="${file}.tmp.$$"
  local content_file="${file}.content.$$"

  printf '%s\n' "$new_content" > "$content_file"

  awk -v hdr="$header" -v cfile="$content_file" '
    $0 == hdr { print; while ((getline line < cfile) > 0) print line; close(cfile); skip=1; next }
    skip && /^## / { skip=0 }
    !skip { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  rm -f "$content_file"
}

ROOT_STATE="$PLANNING_DIR/STATE.md"
ARCHIVED_STATE="$MILESTONE_DIR/STATE.md"

# --- Merge Todos and Decisions ---
root_todos=""
archived_todos=""
root_decisions=""
archived_decisions=""

if [ -f "$ROOT_STATE" ]; then
  root_todos=$(extract_section_items "$ROOT_STATE" "## Todos")
  root_decisions=$(extract_section_items "$ROOT_STATE" "## Key Decisions")
fi

if [ -f "$ARCHIVED_STATE" ]; then
  archived_todos=$(extract_section_items "$ARCHIVED_STATE" "## Todos")
  archived_decisions=$(extract_section_items "$ARCHIVED_STATE" "## Key Decisions")
fi

merged_todos=$(merge_items "$archived_todos" "$root_todos")
merged_decisions=$(merge_items "$archived_decisions" "$root_decisions")

# --- Move files back to root ---
# Move phases
if [ -d "$MILESTONE_DIR/phases" ]; then
  if [ -d "$PLANNING_DIR/phases" ]; then
    # Abort if root phases/ contains any files (active work would be destroyed)
    if [ -n "$(find "$PLANNING_DIR/phases" -type f 2>/dev/null)" ]; then
      echo "Error: root phases/ directory contains files — aborting to prevent data loss" >&2
      echo "  Back up or remove $PLANNING_DIR/phases/ before unarchiving." >&2
      exit 1
    fi
    rm -rf "$PLANNING_DIR/phases"
  fi
  mv "$MILESTONE_DIR/phases" "$PLANNING_DIR/phases"
fi

# Move ROADMAP.md
if [ -f "$MILESTONE_DIR/ROADMAP.md" ]; then
  mv "$MILESTONE_DIR/ROADMAP.md" "$PLANNING_DIR/ROADMAP.md"
fi

# Move STATE.md (archived version is the base)
if [ -f "$ARCHIVED_STATE" ]; then
  mv "$ARCHIVED_STATE" "$ROOT_STATE"
fi

# --- Write merged sections into restored STATE.md ---
if [ -f "$ROOT_STATE" ]; then
  if [ -n "$merged_todos" ]; then
    replace_section "$ROOT_STATE" "## Todos" "$merged_todos"
  fi
  if [ -n "$merged_decisions" ]; then
    replace_section "$ROOT_STATE" "## Key Decisions" "$merged_decisions"
  fi
fi

# --- Clean up milestone dir ---
rm -f "$MILESTONE_DIR/SHIPPED.md" 2>/dev/null || true

# Remove milestone dir if empty (or only has empty subdirs)
find "$MILESTONE_DIR" -type d -empty -delete 2>/dev/null || true
if [ -d "$MILESTONE_DIR" ]; then
  # Check if truly empty (no files remaining)
  if [ -z "$(find "$MILESTONE_DIR" -type f 2>/dev/null)" ]; then
    rm -rf "$MILESTONE_DIR"
  fi
fi

exit 0
