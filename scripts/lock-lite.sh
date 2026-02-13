#!/usr/bin/env bash
set -u

# lock-lite.sh <action> <task-id> [claimed-files...]
# Lightweight file ownership locks for multi-agent conflict prevention.
# action: acquire (create lock), release (remove lock), check (detect conflicts)
# Lock files: .vbw-planning/.locks/{task-id}.lock (JSON)
# Fail-open: exit 0 always. Conflicts are logged to metrics, never blocking.

if [ $# -lt 2 ]; then
  echo "Usage: lock-lite.sh <acquire|release|check> <task-id> [files...]" >&2
  exit 0
fi

ACTION="$1"
TASK_ID="$2"
shift 2

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"
LOCKS_DIR="${PLANNING_DIR}/.locks"
LOCK_FILE="${LOCKS_DIR}/${TASK_ID}.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check feature flag
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  ENABLED=$(jq -r '.v3_lock_lite // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
  [ "$ENABLED" != "true" ] && exit 0
fi

emit_conflict() {
  local conflicting_task="$1"
  local conflicting_file="$2"
  # Extract phase from task ID if possible (format: NN-MM-TN)
  local phase="0"
  phase=$(echo "$TASK_ID" | cut -d'-' -f1 2>/dev/null) || phase="0"
  if [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
    bash "${SCRIPT_DIR}/collect-metrics.sh" file_conflict "$phase" \
      "task=${TASK_ID}" "conflicting_task=${conflicting_task}" "file=${conflicting_file}" 2>/dev/null || true
  fi
  echo "V3 lock conflict: ${conflicting_file} already locked by ${conflicting_task}" >&2
}

case "$ACTION" in
  acquire)
    mkdir -p "$LOCKS_DIR" 2>/dev/null || exit 0

    # Build files JSON array
    FILES_JSON="[]"
    if [ $# -gt 0 ]; then
      FILES_JSON=$(printf '%s\n' "$@" | jq -R '.' | jq -s '.' 2>/dev/null) || FILES_JSON="[]"
    fi

    # Check for conflicts before acquiring
    # zsh compat: if no .lock files exist, glob literal fails -f test and is skipped
    for EXISTING_LOCK in "$LOCKS_DIR"/*.lock; do
      [ ! -f "$EXISTING_LOCK" ] && continue
      [ "$EXISTING_LOCK" = "$LOCK_FILE" ] && continue

      EXISTING_TASK=$(basename "$EXISTING_LOCK" .lock)
      EXISTING_FILES=$(jq -r '.files[]' "$EXISTING_LOCK" 2>/dev/null) || continue

      for CLAIMED_FILE in "$@"; do
        [ -z "$CLAIMED_FILE" ] && continue
        while IFS= read -r existing_file; do
          [ -z "$existing_file" ] && continue
          if [ "$CLAIMED_FILE" = "$existing_file" ]; then
            emit_conflict "$EXISTING_TASK" "$CLAIMED_FILE"
          fi
        done <<< "$EXISTING_FILES"
      done
    done

    # Write lock file
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
    jq -n \
      --arg task_id "$TASK_ID" \
      --arg pid "$$" \
      --arg ts "$TS" \
      --argjson files "$FILES_JSON" \
      '{task_id: $task_id, pid: $pid, timestamp: $ts, files: $files}' \
      > "$LOCK_FILE" 2>/dev/null || exit 0

    echo "acquired"
    ;;

  release)
    if [ -f "$LOCK_FILE" ]; then
      rm -f "$LOCK_FILE" 2>/dev/null || true
      echo "released"
    else
      echo "no_lock"
    fi
    ;;

  check)
    [ ! -d "$LOCKS_DIR" ] && exit 0

    CONFLICTS=0
    # zsh compat: if no .lock files exist, glob literal fails -f test and is skipped
    for EXISTING_LOCK in "$LOCKS_DIR"/*.lock; do
      [ ! -f "$EXISTING_LOCK" ] && continue
      [ "$EXISTING_LOCK" = "$LOCK_FILE" ] && continue

      EXISTING_TASK=$(basename "$EXISTING_LOCK" .lock)
      EXISTING_FILES=$(jq -r '.files[]' "$EXISTING_LOCK" 2>/dev/null) || continue

      for CLAIMED_FILE in "$@"; do
        [ -z "$CLAIMED_FILE" ] && continue
        while IFS= read -r existing_file; do
          [ -z "$existing_file" ] && continue
          if [ "$CLAIMED_FILE" = "$existing_file" ]; then
            emit_conflict "$EXISTING_TASK" "$CLAIMED_FILE"
            CONFLICTS=$((CONFLICTS + 1))
          fi
        done <<< "$EXISTING_FILES"
      done
    done

    if [ "$CONFLICTS" -gt 0 ]; then
      echo "conflicts:${CONFLICTS}"
    else
      echo "clear"
    fi
    ;;

  *)
    echo "Unknown action: $ACTION. Valid: acquire, release, check" >&2
    ;;
esac

exit 0
