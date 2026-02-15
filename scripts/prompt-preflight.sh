#!/bin/bash
set -u
# UserPromptSubmit: Pre-flight validation for VBW commands (non-blocking, exit 0)

PLANNING_DIR=".vbw-planning"
[ -d "$PLANNING_DIR" ] || exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // .content // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

is_expanded_vbw_prompt() {
  local prompt="$1"
  local frontmatter

  # Require YAML frontmatter at the top of the prompt (first non-empty line is ---)
  if ! printf '%s\n' "$prompt" | awk '
    BEGIN { saw = 0 }
    /^[[:space:]]*$/ { next }
    {
      saw = 1
      if ($0 ~ /^[[:space:]]*---[[:space:]]*$/) {
        exit 0
      }
      exit 1
    }
    END {
      if (!saw) {
        exit 1
      }
    }
  '; then
    return 1
  fi

  frontmatter=$(printf '%s\n' "$prompt" | awk '
    BEGIN { in_frontmatter = 0 }
    /^[[:space:]]*---[[:space:]]*$/ {
      if (in_frontmatter == 0) {
        in_frontmatter = 1
        next
      }
      if (in_frontmatter == 1) {
        exit
      }
    }
    in_frontmatter == 1 { print }
  ')

  [ -n "$frontmatter" ] && printf '%s\n' "$frontmatter" | grep -qiE '^[[:space:]]*name:[[:space:]]*vbw:'
}

# GSD Isolation: manage .vbw-session marker
# Create marker when a VBW command is detected. Detection covers:
#   1. Raw slash command input: /vbw:vibe, /vbw:status, etc.
#   2. Expanded command content: YAML frontmatter with "name: vbw:" (Claude Code
#      may pass rendered markdown instead of raw user input).
# Only REMOVE the marker when an explicit non-VBW slash command is detected
# (starts with / but not /vbw:). Plain text follow-ups (e.g., "yes", "ok")
# must NOT clear the marker — they're continuations of the VBW flow.
# Final cleanup happens in session-stop.sh.
if [ -f "$PLANNING_DIR/.gsd-isolation" ]; then
  if echo "$PROMPT" | grep -qi '^/vbw:'; then
    echo "session" > "$PLANNING_DIR/.vbw-session"
  elif is_expanded_vbw_prompt "$PROMPT"; then
    echo "session" > "$PLANNING_DIR/.vbw-session"
  elif printf '%s\n' "$PROMPT" | head -1 | grep -qE '^/[a-zA-Z][a-zA-Z0-9_:-]*(\s|$)' && ! echo "$PROMPT" | grep -qi '^/vbw:'; then
    rm -f "$PLANNING_DIR/.vbw-session"
  fi
  # Plain text prompts: leave marker unchanged (continuation of active flow)
fi

WARNING=""

# Check: /vbw:vibe --execute when no PLAN.md exists
if echo "$PROMPT" | grep -q '/vbw:vibe.*--execute'; then
  CURRENT_PHASE=""
  if [ -f "$PLANNING_DIR/STATE.md" ]; then
    CURRENT_PHASE=$(grep -m1 "^## Current Phase" "$PLANNING_DIR/STATE.md" | sed 's/.*Phase[: ]*//' | tr -d ' ')
  fi

  if [ -n "$CURRENT_PHASE" ]; then
    PHASE_DIR="$PLANNING_DIR/phases/$CURRENT_PHASE"
    PLAN_COUNT=$(find "$PHASE_DIR" -name "PLAN.md" -o -name "*-PLAN.md" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PLAN_COUNT" -eq 0 ]; then
      WARNING="No PLAN.md for phase $CURRENT_PHASE. Run /vbw:vibe to plan first."
    fi
  fi
fi

# Check: /vbw:vibe --archive with incomplete phases
if echo "$PROMPT" | grep -q '/vbw:vibe.*--archive'; then
  if [ -f "$PLANNING_DIR/STATE.md" ]; then
    INCOMPLETE=$(grep -c "status:.*incomplete\|status:.*in.progress\|status:.*pending" "$PLANNING_DIR/STATE.md" 2>/dev/null || echo 0)
    if [ "$INCOMPLETE" -gt 0 ]; then
      WARNING="$INCOMPLETE incomplete phase(s). Review STATE.md before shipping."
    fi
  fi
fi

if [ -n "$WARNING" ]; then
  jq -n --arg msg "$WARNING" '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": ("VBW pre-flight warning: " + $msg)
    }
  }'
fi

exit 0
