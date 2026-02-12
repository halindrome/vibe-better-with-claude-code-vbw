#!/bin/bash
set -u
# file-guard.sh — PreToolUse guard for undeclared file modifications
# Blocks Write/Edit to files not declared in active plan's files_modified.
# V2 enhancement: also checks forbidden_paths from active contract when v2_hard_contracts=true.
# Fail-open design: exit 0 on any error, exit 2 only on definitive violations

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

# Exempt planning artifacts — these are always allowed
case "$FILE_PATH" in
  *.vbw-planning/*|*SUMMARY.md|*VERIFICATION.md|*STATE.md|*CLAUDE.md|*.execution-state.json)
    exit 0
    ;;
esac

# Find project root by walking up from $PWD
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.vbw-planning/phases" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

PROJECT_ROOT=$(find_project_root) || exit 0
PHASES_DIR="$PROJECT_ROOT/.vbw-planning/phases"
[ ! -d "$PHASES_DIR" ] && exit 0

# Normalize path helper
normalize_path() {
  local p="$1"
  if [ -n "$PROJECT_ROOT" ]; then
    p="${p#"$PROJECT_ROOT"/}"
  fi
  p="${p#./}"
  echo "$p"
}

NORM_TARGET=$(normalize_path "$FILE_PATH")

# --- V2 forbidden_paths check from active contract ---
CONFIG_PATH="$PROJECT_ROOT/.vbw-planning/config.json"
V2_HARD=false
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  V2_HARD=$(jq -r '.v2_hard_contracts // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
fi

if [ "$V2_HARD" = "true" ]; then
  CONTRACT_DIR="$PROJECT_ROOT/.vbw-planning/.contracts"
  if [ -d "$CONTRACT_DIR" ]; then
    # Find active contract: match the first plan without a SUMMARY
    for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
      [ ! -f "$PLAN_FILE" ] && continue
      SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
      if [ ! -f "$SUMMARY_FILE" ]; then
        # Extract phase and plan numbers from filename
        BASENAME=$(basename "$PLAN_FILE")
        PHASE_NUM=$(echo "$BASENAME" | sed 's/^\([0-9]*\)-.*/\1/')
        PLAN_NUM=$(echo "$BASENAME" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
        CONTRACT_FILE="${CONTRACT_DIR}/${PHASE_NUM}-${PLAN_NUM}.json"
        if [ -f "$CONTRACT_FILE" ]; then
          # Check forbidden_paths
          FORBIDDEN=$(jq -r '.forbidden_paths[]' "$CONTRACT_FILE" 2>/dev/null) || FORBIDDEN=""
          if [ -n "$FORBIDDEN" ]; then
            while IFS= read -r forbidden; do
              [ -z "$forbidden" ] && continue
              NORM_FORBIDDEN="${forbidden#./}"
              NORM_FORBIDDEN="${NORM_FORBIDDEN%/}"
              if [ "$NORM_TARGET" = "$NORM_FORBIDDEN" ] || [[ "$NORM_TARGET" == "$NORM_FORBIDDEN"/* ]]; then
                echo "Blocked: $NORM_TARGET is a forbidden path in contract (${CONTRACT_FILE})" >&2
                exit 2
              fi
            done <<< "$FORBIDDEN"
          fi
        fi
        break
      fi
    done
  fi
fi

# --- Original file-guard: check files_modified from active plan ---
ACTIVE_PLAN=""
for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
  [ ! -f "$PLAN_FILE" ] && continue
  SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
  if [ ! -f "$SUMMARY_FILE" ]; then
    ACTIVE_PLAN="$PLAN_FILE"
    break
  fi
done

# No active plan found — fail-open
[ -z "$ACTIVE_PLAN" ] && exit 0

# Extract files_modified from YAML frontmatter
DECLARED_FILES=$(awk '
  BEGIN { in_front=0; in_files=0 }
  /^---$/ {
    if (in_front == 0) { in_front=1; next }
    else { exit }
  }
  in_front && /^files_modified:/ { in_files=1; next }
  in_front && in_files && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    gsub(/["'"'"']/, "")
    print
    next
  }
  in_front && in_files && /^[^[:space:]]/ { in_files=0 }
' "$ACTIVE_PLAN" 2>/dev/null) || exit 0

# No files_modified declared — fail-open
[ -z "$DECLARED_FILES" ] && exit 0

# Check if target file is in declared files
while IFS= read -r declared; do
  [ -z "$declared" ] && continue
  NORM_DECLARED=$(normalize_path "$declared")
  if [ "$NORM_TARGET" = "$NORM_DECLARED" ]; then
    exit 0
  fi
done <<< "$DECLARED_FILES"

# File not declared — block the write
echo "Blocked: $NORM_TARGET is not in active plan's files_modified ($ACTIVE_PLAN)" >&2
exit 2
