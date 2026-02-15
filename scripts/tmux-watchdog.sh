#!/bin/bash
set -u
# tmux-watchdog.sh — Terminate orphaned agents when tmux session detaches
#
# Usage: tmux-watchdog.sh [session-name]
#
# Polls `tmux list-clients -t SESSION` every 5 seconds. Requires 2 consecutive
# empty results before cleanup. On confirmed detach: reads PIDs from
# agent-pid-tracker.sh list, sends SIGTERM, waits 3s, sends SIGKILL if needed.
# Logs to stderr. Exits when session is gone (not just detached).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR=".vbw-planning"

# --- Session name resolution ---
SESSION="${1:-}"
if [ -z "$SESSION" ]; then
  # Auto-detect from $TMUX environment variable
  # Format: /path/to/socket,server_pid,session_num
  if [ -n "${TMUX:-}" ]; then
    SESSION=$(tmux display-message -p '#S' 2>/dev/null || true)
  fi
fi

if [ -z "$SESSION" ]; then
  echo "ERROR: No session name provided and not running in tmux" >&2
  exit 1
fi

LOG="$PLANNING_DIR/.watchdog.log"
mkdir -p "$PLANNING_DIR"

log() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $*" >> "$LOG" 2>/dev/null || echo "[$timestamp] $*" >&2
}

log "Watchdog started for session: $SESSION (PID=$$)"

# --- Main polling loop ---
consecutive_empty=0
while true; do
  # Check if session still exists
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "Session $SESSION no longer exists, exiting"
    break
  fi

  # Poll for attached clients
  CLIENTS=$(tmux list-clients -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')

  if [ "${CLIENTS:-0}" -eq 0 ]; then
    consecutive_empty=$((consecutive_empty + 1))
    log "No clients attached (consecutive: $consecutive_empty)"

    if [ "$consecutive_empty" -ge 2 ]; then
      log "Session detached (2 consecutive polls), cleaning up agents"

      # Read active agent PIDs
      PIDS=""
      if [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
        PIDS=$(bash "$SCRIPT_DIR/agent-pid-tracker.sh" list 2>/dev/null || true)
      fi

      if [ -z "$PIDS" ]; then
        log "No active agent PIDs to terminate"
      else
        # Terminate with SIGTERM
        for pid in $PIDS; do
          if kill -0 "$pid" 2>/dev/null; then
            log "Sending SIGTERM to agent PID $pid"
            kill -TERM "$pid" 2>/dev/null || true
          fi
        done

        # Wait 3 seconds for graceful shutdown
        sleep 3

        # SIGKILL fallback for survivors
        for pid in $PIDS; do
          if kill -0 "$pid" 2>/dev/null; then
            log "Agent PID $pid survived SIGTERM, sending SIGKILL"
            kill -KILL "$pid" 2>/dev/null || true
          fi
        done

        log "Agent cleanup complete"
      fi

      # Clean up PID file
      if [ -f "$PLANNING_DIR/.agent-pids" ]; then
        rm -f "$PLANNING_DIR/.agent-pids" 2>/dev/null || true
        log "Removed .agent-pids file"
      fi

      # Exit after cleanup
      log "Watchdog exiting"
      break
    fi
  else
    # Clients attached, reset counter
    if [ "$consecutive_empty" -gt 0 ]; then
      log "Client attached, resetting empty counter"
    fi
    consecutive_empty=0
  fi

  sleep 5
done

exit 0
