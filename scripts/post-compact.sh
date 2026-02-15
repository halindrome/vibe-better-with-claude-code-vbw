#!/bin/bash
set -u
# SessionStart(compact) hook: Remind agent to re-read key files after compaction
# Reads compaction context from stdin, detects agent role, suggests re-reads

INPUT=$(cat)

# Clean up cost tracking files and compaction marker (stale after compaction)
# Preserve .active-agent and .active-agent-count — agents may still be running
# after compaction. These are cleaned up by agent-stop.sh and session-stop.sh.
rm -f .vbw-planning/.cost-ledger.json .vbw-planning/.compaction-marker 2>/dev/null

# Try to identify agent role from input context
ROLE=""
for pattern in vbw-lead vbw-dev vbw-qa vbw-scout vbw-debugger vbw-architect; do
  if echo "$INPUT" | grep -qi "$pattern"; then
    ROLE="$pattern"
    break
  fi
done

case "$ROLE" in
  vbw-lead)
    FILES="STATE.md, ROADMAP.md, config.json, and current phase plans"
    ;;
  vbw-dev)
    FILES="your assigned plan file, SUMMARY.md template, and relevant source files"
    ;;
  vbw-qa)
    FILES="SUMMARY.md files under review, verification criteria, and gap reports"
    ;;
  vbw-scout)
    FILES="research notes, REQUIREMENTS.md, and any scout-specific findings"
    ;;
  vbw-debugger)
    FILES="reproduction steps, hypothesis log, and related source files"
    ;;
  vbw-architect)
    FILES="REQUIREMENTS.md, ROADMAP.md, phase structure, and architecture decisions"
    ;;
  *)
    FILES="STATE.md, your assigned task context, and any in-progress files"
    ;;
esac

# --- Restore agent state snapshot ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_CONTEXT=""
if [ -f ".vbw-planning/.execution-state.json" ] && [ -f "$SCRIPT_DIR/snapshot-resume.sh" ]; then
  SNAP_PHASE=$(jq -r '.phase // ""' ".vbw-planning/.execution-state.json" 2>/dev/null)
  if [ -n "$SNAP_PHASE" ]; then
    SNAP_PATH=$(bash "$SCRIPT_DIR/snapshot-resume.sh" restore "$SNAP_PHASE" 2>/dev/null) || SNAP_PATH=""
    if [ -n "$SNAP_PATH" ] && [ -f "$SNAP_PATH" ]; then
      SNAP_PLAN=$(jq -r '.execution_state.current_plan // "unknown"' "$SNAP_PATH" 2>/dev/null)
      SNAP_STATUS=$(jq -r '.execution_state.status // "unknown"' "$SNAP_PATH" 2>/dev/null)
      SNAP_COMMITS=$(jq -r '.recent_commits | join(", ")' "$SNAP_PATH" 2>/dev/null) || SNAP_COMMITS=""
      SNAPSHOT_CONTEXT=" Pre-compaction state: phase=${SNAP_PHASE}, plan=${SNAP_PLAN}, status=${SNAP_STATUS}."
      if [ -n "$SNAP_COMMITS" ]; then
        SNAPSHOT_CONTEXT="${SNAPSHOT_CONTEXT} Recent commits: ${SNAP_COMMITS}."
      fi
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
      echo "[$TIMESTAMP] Snapshot restored: $SNAP_PATH phase=$SNAP_PHASE" >> ".vbw-planning/.hook-errors.log" 2>/dev/null || true
    fi
  fi
fi

jq -n --arg role "${ROLE:-unknown}" --arg files "$FILES" --arg snap "${SNAPSHOT_CONTEXT:-}" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ("Context was compacted. Agent role: " + $role + ". Re-read these key files from disk: " + $files + $snap)
  }
}'

exit 0
