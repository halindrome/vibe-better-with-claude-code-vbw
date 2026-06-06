#!/usr/bin/env bash
set -u

# detect-workflows-support.sh — best-effort detection of Claude Dynamic Workflows availability.
#
# Dynamic Workflows are a Claude Code *runtime* feature: a workflow is a JS script
# the runtime executes in the background to orchestrate many subagents. A shell
# script cannot prove the running CLI version ships them, so this reports the
# strongest signal available from disk/env: whether workflows are NOT disabled.
# The executor resolver treats "supported" as "eligible to attempt"; final
# availability is confirmed by the runtime at invocation. This single signal gates
# BOTH workflow invocation surfaces — the per-request `ultracode` keyword and the
# first-class `Workflow` tool (direct programmatic dispatch). When support cannot be
# confirmed (no jq, parse failure), detection FAILS CLOSED (unsupported) so VBW
# keeps using its proven team/subagent/direct delegation — behavior stays
# identical to today wherever the feature is absent or unverifiable.
#
# Usage:
#   bash scripts/detect-workflows-support.sh [project-dir]   # key=value lines
#   bash scripts/detect-workflows-support.sh --status [project-dir]  # prints: supported|unsupported
#
# Default output (key=value):
#   workflows_supported=true|false
#   workflows_reason=<short reason>
#
# Disable signals (any present -> unsupported):
#   - CLAUDE_CODE_DISABLE_WORKFLOWS truthy (env kill switch, read at startup)
#   - "disableWorkflows": true in the effective merged settings.json
#     (user settings < project .claude/settings.json < project .claude/settings.local.json)
#   - "enableWorkflows": false in the effective merged settings.json (Pro opt-in
#     explicitly declined — see note below)
#
# Two distinct settings keys exist in practice:
#   - disableWorkflows (bool): the org/user kill switch documented at
#     https://code.claude.com/docs/en/workflows.
#   - enableWorkflows  (bool): the Pro opt-in toggle that the /config "Dynamic
#     workflows" row and the cloud admin settings actually persist (observed
#     empirically; not on the public workflows page). On Pro the feature is OFF
#     until enableWorkflows is true, so enableWorkflows:false is a definitive
#     "unsupported" signal that disableWorkflows alone does not cover.
#
# Always exits 0 — detection must never break a caller.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve CLAUDE_DIR (user config dir) via the canonical resolver. Best-effort.
CLAUDE_DIR=""
# shellcheck source=resolve-claude-dir.sh
if [ -f "$SCRIPT_DIR/resolve-claude-dir.sh" ]; then
  . "$SCRIPT_DIR/resolve-claude-dir.sh" 2>/dev/null || true
fi

STATUS_ONLY=false
if [ "${1:-}" = "--status" ]; then
  STATUS_ONLY=true
  shift
fi

PROJECT_DIR="${1:-$PWD}"

emit() {
  local supported="$1" reason="$2"
  if [ "$STATUS_ONLY" = true ]; then
    if [ "$supported" = "true" ]; then echo "supported"; else echo "unsupported"; fi
  else
    echo "workflows_supported=$supported"
    echo "workflows_reason=$reason"
  fi
  exit 0
}

is_truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# 1. Environment kill switch wins (read at startup, applies on every surface).
if [ -n "${CLAUDE_CODE_DISABLE_WORKFLOWS:-}" ] && is_truthy "$CLAUDE_CODE_DISABLE_WORKFLOWS"; then
  emit false "disabled by CLAUDE_CODE_DISABLE_WORKFLOWS"
fi

# 2. Need jq to inspect settings. Fail closed if unavailable.
if ! command -v jq >/dev/null 2>&1; then
  emit false "jq unavailable; cannot confirm support"
fi

# 3. Compute effective disableWorkflows AND enableWorkflows across settings files,
#    lowest precedence first so a higher-precedence file overrides a lower one.
EFFECTIVE_DISABLE=""  # "", "true", or "false"
EFFECTIVE_ENABLE=""   # "", "true", or "false"
for settings in \
  "${CLAUDE_DIR:+$CLAUDE_DIR/settings.json}" \
  "$PROJECT_DIR/.claude/settings.json" \
  "$PROJECT_DIR/.claude/settings.local.json"; do
  [ -n "$settings" ] || continue
  [ -f "$settings" ] || continue
  dvalue="$(jq -r 'if has("disableWorkflows") then (.disableWorkflows | tostring) else "" end' "$settings" 2>/dev/null || echo "")"
  case "$dvalue" in
    true|false) EFFECTIVE_DISABLE="$dvalue" ;;
  esac
  evalue="$(jq -r 'if has("enableWorkflows") then (.enableWorkflows | tostring) else "" end' "$settings" 2>/dev/null || echo "")"
  case "$evalue" in
    true|false) EFFECTIVE_ENABLE="$evalue" ;;
  esac
done

# The kill switch wins over the opt-in.
if [ "$EFFECTIVE_DISABLE" = "true" ]; then
  emit false "disabled via disableWorkflows in settings.json"
fi
if [ "$EFFECTIVE_ENABLE" = "false" ]; then
  emit false "disabled via enableWorkflows:false in settings.json (Pro opt-in declined)"
fi
if [ "$EFFECTIVE_ENABLE" = "true" ]; then
  emit true "enabled via enableWorkflows in settings.json"
fi

emit true "no disable signal detected"
