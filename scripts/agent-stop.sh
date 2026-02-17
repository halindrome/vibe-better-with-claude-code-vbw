#!/bin/bash
set -u
# SubagentStop hook: Decrement active agent count and unregister PID
# Uses reference counting so concurrent agents (e.g., Scout + Lead) don't
# delete the marker while siblings are still running.
# Unregisters agent PID from tmux watchdog tracking.
# Final cleanup happens in session-stop.sh.

INPUT=$(cat)
PLANNING_DIR=".vbw-planning"
COUNT_FILE="$PLANNING_DIR/.active-agent-count"
LOCK_DIR="$PLANNING_DIR/.active-agent-count.lock"

acquire_lock() {
  local attempts=0
  local max_attempts=100
  local now lock_mtime age
  while [ "$attempts" -lt "$max_attempts" ]; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi

    attempts=$((attempts + 1))

    # Stale lock guard: if lock persists for >5s, clear and retry.
    if [ "$attempts" -eq 50 ] && [ -d "$LOCK_DIR" ]; then
      now=$(date +%s)
      if [ "$(uname)" = "Darwin" ]; then
        lock_mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
      else
        lock_mtime=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
      fi
      age=$((now - lock_mtime))
      if [ "$age" -gt 5 ]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
      fi
    fi

    sleep 0.01
  done
  # Could not acquire lock — proceed without it (best-effort).
  return 1
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

read_count() {
  local raw
  raw=$(cat "$COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
  if echo "$raw" | grep -Eq '^[0-9]+$'; then
    printf '%s' "$raw"
  else
    printf '0'
  fi
}

decrement_or_cleanup() {
  local count

  if [ -f "$COUNT_FILE" ]; then
    count=$(read_count)
    # Corrupted count + active marker => treat as one active agent left.
    if [ "$count" -le 0 ] && [ -f "$PLANNING_DIR/.active-agent" ]; then
      count=1
    fi

    count=$((count - 1))
    if [ "$count" -le 0 ]; then
      rm -f "$PLANNING_DIR/.active-agent" "$COUNT_FILE"
    else
      echo "$count" > "$COUNT_FILE"
    fi
  elif [ -f "$PLANNING_DIR/.active-agent" ]; then
    # Legacy: no count file but marker exists — remove (single agent case)
    rm -f "$PLANNING_DIR/.active-agent"
  fi
}

if acquire_lock; then
  trap 'release_lock' EXIT INT TERM
  decrement_or_cleanup
  release_lock
  trap - EXIT INT TERM
else
  # Lock unavailable — proceed best-effort without lock.
  decrement_or_cleanup
fi

# Unregister agent PID
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_PID=$(echo "$INPUT" | jq -r '.pid // ""' 2>/dev/null)
if [ -n "$AGENT_PID" ] && [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
  bash "$SCRIPT_DIR/agent-pid-tracker.sh" unregister "$AGENT_PID" 2>/dev/null || true
fi

# Auto-close tmux pane if recorded at start
PANE_MAP="$PLANNING_DIR/.agent-panes"
if [ -n "${TMUX:-}" ] && [ -n "$AGENT_PID" ] && [ -f "$PANE_MAP" ]; then
  PANE_ID=$(awk -v p="$AGENT_PID" '$1 == p { print $2; exit }' "$PANE_MAP" 2>/dev/null)
  if [ -n "$PANE_ID" ]; then
    # Remove entry from map
    grep -v "^${AGENT_PID} " "$PANE_MAP" > "${PANE_MAP}.tmp" 2>/dev/null || true
    mv "${PANE_MAP}.tmp" "$PANE_MAP" 2>/dev/null || true
    # Kill pane (delay briefly so agent process exits cleanly first)
    (sleep 1 && tmux kill-pane -t "$PANE_ID" 2>/dev/null || true) &
  fi
fi

exit 0
