#!/usr/bin/env bash
set -u

# resolve-executor.sh — decide whether a wide/parallel step should run through the
# Claude Dynamic Workflows executor or fall back to VBW's existing delegation.
#
# This is an orthogonal predicate, NOT a replacement for
# resolve-execute-delegation-mode.sh. It answers ONE question: "workflow or not?"
# Callers run their normal team/subagent/direct resolution whenever the answer is
# "fallback", so existing routing is unchanged when workflows are off/unavailable.
#
# Usage:
#   resolve-executor.sh --fanout <N> [options]      # prints: executor=… / reason=…
#   resolve-executor.sh --mode --fanout <N> [opts]  # prints just: workflow|fallback
#
# Options:
#   --fanout N           Independent parallel units the step would fan out to (required).
#   --config PATH        config.json to read the `workflows` mode (default .vbw-planning/config.json).
#   --project DIR        Project dir for runtime support detection (default: PWD).
#   --threshold N        auto-mode fan-out threshold to prefer workflows (default 25).
#   --min-fanout N       Below this, a step is never "wide" enough for a workflow (default 2).
#   --workflows-mode VAL Override the config value (always|auto|never|…); skips config read.
#   --supported VAL      Override runtime detection (true|false); skips detect probe.
#   --mode               Print only the decision token (workflow|fallback).
#
# Decision:
#   workflows=never                      -> fallback
#   runtime unsupported                  -> fallback
#   fanout not an integer / < min-fanout -> fallback
#   workflows=always (fanout >= min)     -> workflow
#   workflows=auto, fanout >= threshold  -> workflow
#   workflows=auto, fanout <  threshold  -> fallback
#   unknown workflows value              -> fallback (conservative)
#
# Always exits 0 — a routing predicate must never break the caller. Fails safe to
# "fallback" so behavior is identical to today whenever anything is uncertain.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FANOUT=""
CONFIG_PATH=".vbw-planning/config.json"
PROJECT_DIR="$PWD"
THRESHOLD=25
MIN_FANOUT=2
MODE_OVERRIDE=""
SUPPORTED_OVERRIDE=""
TOKEN_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --fanout) FANOUT="${2:-}"; shift 2 ;;
    --fanout=*) FANOUT="${1#--fanout=}"; shift ;;
    --config) CONFIG_PATH="${2:-}"; shift 2 ;;
    --config=*) CONFIG_PATH="${1#--config=}"; shift ;;
    --project) PROJECT_DIR="${2:-}"; shift 2 ;;
    --project=*) PROJECT_DIR="${1#--project=}"; shift ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    --threshold=*) THRESHOLD="${1#--threshold=}"; shift ;;
    --min-fanout) MIN_FANOUT="${2:-}"; shift 2 ;;
    --min-fanout=*) MIN_FANOUT="${1#--min-fanout=}"; shift ;;
    --workflows-mode) MODE_OVERRIDE="${2:-}"; shift 2 ;;
    --workflows-mode=*) MODE_OVERRIDE="${1#--workflows-mode=}"; shift ;;
    --supported) SUPPORTED_OVERRIDE="${2:-}"; shift 2 ;;
    --supported=*) SUPPORTED_OVERRIDE="${1#--supported=}"; shift ;;
    --mode) TOKEN_ONLY=true; shift ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) shift ;;
  esac
done

emit() {
  local decision="$1" reason="$2"
  if [ "$TOKEN_ONLY" = true ]; then
    echo "$decision"
  else
    echo "executor=$decision"
    echo "reason=$reason"
  fi
  exit 0
}

is_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac }

# Resolve the workflows mode (canonicalized).
if [ -n "$MODE_OVERRIDE" ]; then
  WF_MODE="$(bash "$SCRIPT_DIR/normalize-workflows-mode.sh" --value "$MODE_OVERRIDE" 2>/dev/null || echo "$MODE_OVERRIDE")"
else
  WF_MODE="$(bash "$SCRIPT_DIR/normalize-workflows-mode.sh" "$CONFIG_PATH" 2>/dev/null || echo "auto")"
fi

# Cheap, no-detection exits first.
[ "$WF_MODE" = "never" ] && emit fallback "workflows_never"

if ! is_int "$FANOUT"; then
  emit fallback "invalid_fanout"
fi
if ! is_int "$MIN_FANOUT"; then MIN_FANOUT=2; fi
if ! is_int "$THRESHOLD"; then THRESHOLD=25; fi

if [ "$FANOUT" -lt "$MIN_FANOUT" ]; then
  emit fallback "fanout_below_minimum:$FANOUT<$MIN_FANOUT"
fi

# Resolve runtime support (detection probe, unless overridden).
if [ -n "$SUPPORTED_OVERRIDE" ]; then
  case "$(printf '%s' "$SUPPORTED_OVERRIDE" | tr '[:upper:]' '[:lower:]')" in
    true|supported|1|yes) SUPPORTED="true" ;;
    *) SUPPORTED="false" ;;
  esac
else
  if [ "$(bash "$SCRIPT_DIR/detect-workflows-support.sh" --status "$PROJECT_DIR" 2>/dev/null || echo unsupported)" = "supported" ]; then
    SUPPORTED="true"
  else
    SUPPORTED="false"
  fi
fi

[ "$SUPPORTED" = "true" ] || emit fallback "workflows_unsupported"

case "$WF_MODE" in
  always)
    emit workflow "workflows_always:fanout=$FANOUT"
    ;;
  auto)
    if [ "$FANOUT" -ge "$THRESHOLD" ]; then
      emit workflow "auto_fanout_meets_threshold:$FANOUT>=$THRESHOLD"
    else
      emit fallback "auto_fanout_below_threshold:$FANOUT<$THRESHOLD"
    fi
    ;;
  *)
    emit fallback "unknown_workflows_mode:$WF_MODE"
    ;;
esac
