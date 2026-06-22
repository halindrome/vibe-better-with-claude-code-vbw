#!/bin/bash
set -u
# workflow-worker-register.sh <register|release> <session_id> [role] [pid]
#
# Registers/unregisters a workflow-executor worker as an active VBW agent.
#
# Why this exists: the SubagentStart / SubagentStop hooks (which normally run
# agent-start.sh / agent-stop.sh) do NOT fire for workers spawned via the
# Workflow tool's agent() primitive — only for Task/Team subagents. file-guard.sh
# authorizes a worker's product-file Write/Edit by reading the per-session
# active-agent count (.vbw-planning/.active-agents/<session_id>/active-agent-count).
# With no SubagentStart, that count is never incremented, the worker is
# misclassified as the orchestrator, and its product-file writes are blocked
# ("orchestrator cannot write product files during delegated workflow").
#
# The workflow executor therefore injects a register call into each worker's
# prompt (run before the first write) and a release call (run at the very end),
# mirroring how lease_locks / two_phase_completion are relocated into the worker.
#
# Invoked as a SINGLE bounded command (no pipes / redirects / cd) so consumer
# PreToolUse hooks do not block it mid-run. Always exits 0 (fail-open) — a
# registration failure must never abort a worker.

VERB="${1:-}"
SESSION_ID="${2:-}"
ROLE="${3:-dev}"
PID="${4:-$PPID}"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
[ -d "$PLANNING_DIR" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  # shellcheck source=lib/active-agent-state.sh
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
else
  exit 0
fi

# Resolve the session id: explicit arg wins; otherwise fall back to the
# CLAUDE_SESSION_ID env var. The per-session bucket file-guard reads is keyed by
# the Write payload's .session_id (the main session id), so we must register
# into that exact bucket — NOT the aggregate __vbw_legacy_global bucket, which
# file-guard ignores when a safe session id is present.
if ! vbw_active_agent_is_safe_session_id "$SESSION_ID"; then
  SESSION_ID="${CLAUDE_SESSION_ID:-}"
fi

# Normalize the role (workflow product workers are Dev by default).
ROLE_NORM=""
if ROLE_NORM=$(vbw_active_agent_normalize_role "$ROLE" 2>/dev/null); then
  :
else
  ROLE_NORM=""
fi
[ -n "$ROLE_NORM" ] || ROLE_NORM="dev"

# Build an input payload carrying the session id so the state helpers register
# into the per-session bucket (vbw_active_agent_session_id reads .session_id).
INPUT="{}"
if vbw_active_agent_is_safe_session_id "$SESSION_ID"; then
  INPUT=$(printf '{"session_id":"%s"}' "$SESSION_ID")
fi

case "$VERB" in
  register|start|acquire)
    vbw_active_agent_start "$PLANNING_DIR" "$INPUT" "$ROLE_NORM" "$PID"
    echo "registered ${ROLE_NORM} worker (session=${SESSION_ID:-legacy})"
    ;;
  release|stop|unregister)
    vbw_active_agent_stop "$PLANNING_DIR" "$INPUT" "$ROLE_NORM" "$PID"
    echo "released ${ROLE_NORM} worker (session=${SESSION_ID:-legacy})"
    ;;
  *)
    # Unknown verb — no-op, fail-open.
    exit 0
    ;;
esac

exit 0
