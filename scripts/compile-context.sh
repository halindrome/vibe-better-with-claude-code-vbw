#!/usr/bin/env bash
set -euo pipefail

# compile-context.sh <phase-number> <role> [phases-dir] [plan-path]
# Produces .context-{role}.md in the phase directory with role-specific context.
# Exit 0 on success, exit 1 when phase directory not found.

if [ $# -lt 2 ]; then
  echo "Usage: compile-context.sh <phase-number> <role> [phases-dir]" >&2
  exit 1
fi

PHASE="$1"
ROLE="$2"
PHASES_DIR="${3:-.vbw-planning/phases}"
PLANNING_DIR=".vbw-planning"
PLAN_PATH="${4:-}"

# Strip leading zeros for ROADMAP matching (ROADMAP uses "Phase 2:", not "Phase 02:")
PHASE_NUM=$(echo "$PHASE" | sed 's/^0*//')
if [ -z "$PHASE_NUM" ]; then PHASE_NUM="0"; fi

# --- Find phase directory (tolerate both padded and unpadded input) ---
PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PHASE}-*" 2>/dev/null | head -1)
if [ -z "$PHASE_DIR" ]; then
  PADDED=$(printf "%02d" "$PHASE_NUM")
  PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PADDED}-*" 2>/dev/null | head -1)
fi
if [ -z "$PHASE_DIR" ]; then
  echo "Phase ${PHASE} directory not found" >&2
  exit 1
fi

# --- Extract phase metadata from ROADMAP.md ---
ROADMAP="$PLANNING_DIR/ROADMAP.md"

PHASE_SECTION=""
PHASE_GOAL="Not available"
PHASE_REQS="Not available"
PHASE_SUCCESS="Not available"

if [ -f "$ROADMAP" ]; then
  PHASE_SECTION=$(sed -n "/^### Phase ${PHASE_NUM}:/,/^### Phase [0-9]/p" "$ROADMAP" 2>/dev/null | sed '$d') || true
  if [ -n "$PHASE_SECTION" ]; then
    PHASE_GOAL=$(echo "$PHASE_SECTION" | grep '^\*\*Goal:\*\*' 2>/dev/null | sed 's/\*\*Goal:\*\* *//' ) || PHASE_GOAL="Not available"
    PHASE_REQS=$(echo "$PHASE_SECTION" | grep '^\*\*Reqs:\*\*' 2>/dev/null | sed 's/\*\*Reqs:\*\* *//' ) || PHASE_REQS="Not available"
    PHASE_SUCCESS=$(echo "$PHASE_SECTION" | grep '^\*\*Success:\*\*' 2>/dev/null | sed 's/\*\*Success:\*\* *//' ) || PHASE_SUCCESS="Not available"
  fi
fi

# --- Build REQ grep pattern from comma-separated REQ IDs ---
REQ_PATTERN=""
if [ "$PHASE_REQS" != "Not available" ] && [ -n "$PHASE_REQS" ]; then
  REQ_PATTERN=$(echo "$PHASE_REQS" | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//' | paste -sd '|' -) || true
fi

# --- Role-specific output ---
case "$ROLE" in
  lead)
    {
      echo "## Phase ${PHASE} Context (Compiled)"
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      echo ""
      echo "### Success Criteria"
      echo "$PHASE_SUCCESS"
      echo ""
      echo "### Requirements (${PHASE_REQS})"
      if [ -n "$REQ_PATTERN" ] && [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null || echo "No matching requirements found"
      else
        echo "No matching requirements found"
      fi
      echo ""
      # Count total reqs for awareness
      TOTAL_REQS=$(grep -c '^\- \[' "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null || echo "0")
      MATCHED_REQS=0
      if [ "$PHASE_REQS" != "Not available" ] && [ -n "$PHASE_REQS" ]; then
        MATCHED_REQS=$(echo "$PHASE_REQS" | tr ',' '\n' | wc -l | tr -d ' ')
      fi
      OTHERS=$((TOTAL_REQS - MATCHED_REQS))
      if [ "$OTHERS" -gt 0 ]; then
        echo "(${OTHERS} other requirements exist for other phases -- not shown)"
      fi
      echo ""
      echo "### Active Decisions"
      if [ -f "$PLANNING_DIR/STATE.md" ]; then
        DECISIONS=$(sed -n '/^## Decisions/,/^## [A-Z]/p' "$PLANNING_DIR/STATE.md" 2>/dev/null | sed '$d' | tail -n +2) || true
        if [ -n "$DECISIONS" ]; then
          echo "$DECISIONS"
        else
          echo "None"
        fi
      else
        echo "None"
      fi
    } > "${PHASE_DIR}/.context-lead.md"
    ;;

  dev)
    {
      echo "## Phase ${PHASE} Context"
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
        CONVENTIONS=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
        if [ -n "$CONVENTIONS" ]; then
          echo ""
          echo "### Conventions"
          echo "$CONVENTIONS"
        fi
      fi
      # --- Skill bundling (REQ-12) ---
      if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
        SKILLS=$(sed -n '/^---$/,/^---$/p' "$PLAN_PATH" | grep 'skills_used:' | sed 's/skills_used: *\[//' | sed 's/\]//' | tr ',' '\n' | sed 's/^ *//;s/ *$//;s/^"//;s/"$//' | grep -v '^$' || true)
        if [ -n "$SKILLS" ]; then
          echo ""
          echo "### Skills Reference"
          echo ""
          while IFS= read -r skill; do
            SKILL_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/${skill}/SKILL.md"
            if [ -f "$SKILL_FILE" ]; then
              echo "#### ${skill}"
              cat "$SKILL_FILE"
              echo ""
            fi
          done <<< "$SKILLS"
        fi
      fi
    } > "${PHASE_DIR}/.context-dev.md"
    ;;

  qa)
    {
      echo "## Phase ${PHASE} Verification Context"
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      echo ""
      echo "### Success Criteria"
      echo "$PHASE_SUCCESS"
      echo ""
      echo "### Requirements to Verify"
      if [ -n "$REQ_PATTERN" ] && [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null || echo "No matching requirements found"
      else
        echo "No matching requirements found"
      fi
      if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
        CONVENTIONS=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
        if [ -n "$CONVENTIONS" ]; then
          echo ""
          echo "### Conventions to Check"
          echo "$CONVENTIONS"
        fi
      fi
    } > "${PHASE_DIR}/.context-qa.md"
    ;;

  *)
    echo "Unknown role: $ROLE. Valid roles: lead, dev, qa" >&2
    exit 1
    ;;
esac

echo "${PHASE_DIR}/.context-${ROLE}.md"
