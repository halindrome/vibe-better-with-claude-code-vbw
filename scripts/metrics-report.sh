#!/usr/bin/env bash
set -u

# metrics-report.sh [phase]
# Generates a markdown observability report from metrics JSONL.
# Aggregates 7 V2 metrics: task_latency, tokens_per_task, gate_failure_rate,
# lease_conflicts, resume_success, regression_escape, fallback_pct.
# Output: markdown table to stdout.
# Exit: 0 always.

PLANNING_DIR=".vbw-planning"
METRICS_FILE="${PLANNING_DIR}/.metrics/run-metrics.jsonl"
EVENTS_FILE="${PLANNING_DIR}/.events/event-log.jsonl"

FILTER_PHASE="${1:-}"

if [ ! -f "$METRICS_FILE" ] && [ ! -f "$EVENTS_FILE" ]; then
  echo "# Metrics Report"
  echo ""
  echo "No metrics data found. Enable \`v3_metrics=true\` and \`v3_event_log=true\` in config."
  exit 0
fi

echo "# VBW Observability Report"
echo ""
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")"
if [ -n "$FILTER_PHASE" ]; then
  echo "Phase filter: ${FILTER_PHASE}"
fi
echo ""

# --- Metric 1: Task Latency ---
echo "## Task Latency"
if [ -f "$EVENTS_FILE" ]; then
  TASK_STARTS=$(jq -s '[.[] | select(.event == "task_started")]' "$EVENTS_FILE" 2>/dev/null || echo "[]")
  TASK_CONFIRMS=$(jq -s '[.[] | select(.event == "task_completed_confirmed")]' "$EVENTS_FILE" 2>/dev/null || echo "[]")
  START_COUNT=$(echo "$TASK_STARTS" | jq 'length' 2>/dev/null || echo "0")
  CONFIRM_COUNT=$(echo "$TASK_CONFIRMS" | jq 'length' 2>/dev/null || echo "0")
  echo "- Tasks started: ${START_COUNT}"
  echo "- Tasks confirmed: ${CONFIRM_COUNT}"
else
  echo "- No event log data"
fi
echo ""

# --- Metric 2: Tokens per Task ---
echo "## Tokens per Task"
if [ -f "$METRICS_FILE" ]; then
  OVERAGE_COUNT=$(jq -s '[.[] | select(.event == "token_overage")] | length' "$METRICS_FILE" 2>/dev/null || echo "0")
  echo "- Token overage events: ${OVERAGE_COUNT}"
else
  echo "- No metrics data"
fi
echo ""

# --- Metric 3: Gate Failure Rate ---
echo "## Gate Failure Rate"
if [ -f "$EVENTS_FILE" ]; then
  GATE_PASSED=$(jq -s '[.[] | select(.event == "gate_passed")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  GATE_FAILED=$(jq -s '[.[] | select(.event == "gate_failed")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  GATE_TOTAL=$((GATE_PASSED + GATE_FAILED))
  if [ "$GATE_TOTAL" -gt 0 ]; then
    FAIL_RATE=$((GATE_FAILED * 100 / GATE_TOTAL))
    echo "- Passed: ${GATE_PASSED} / Failed: ${GATE_FAILED} / Total: ${GATE_TOTAL}"
    echo "- Failure rate: ${FAIL_RATE}%"
  else
    echo "- No gate events recorded"
  fi
else
  echo "- No event log data"
fi
echo ""

# --- Metric 4: Lease Conflicts ---
echo "## Lease Conflicts"
if [ -f "$METRICS_FILE" ]; then
  CONFLICTS=$(jq -s '[.[] | select(.event == "file_conflict")] | length' "$METRICS_FILE" 2>/dev/null || echo "0")
  echo "- Conflicts detected: ${CONFLICTS}"
else
  echo "- No metrics data"
fi
echo ""

# --- Metric 5: Resume Success ---
echo "## Resume Success"
if [ -f "$EVENTS_FILE" ]; then
  RESUMES=$(jq -s '[.[] | select(.event == "snapshot_restored" or .event == "state_recovered")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  echo "- Successful resumes: ${RESUMES}"
else
  echo "- No event log data"
fi
echo ""

# --- Metric 6: Regression Escape ---
echo "## Regression Escape"
if [ -f "$EVENTS_FILE" ]; then
  REJECTIONS=$(jq -s '[.[] | select(.event == "task_completion_rejected")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  echo "- Task completion rejections: ${REJECTIONS}"
else
  echo "- No event log data"
fi
echo ""

# --- Metric 7: Fallback Percentage ---
echo "## Fallback Executions"
if [ -f "$METRICS_FILE" ]; then
  SMART_ROUTES=$(jq -s '[.[] | select(.event == "smart_route")] | length' "$METRICS_FILE" 2>/dev/null || echo "0")
  FALLBACKS=$(jq -s '[.[] | select(.event == "smart_route") | select(.data.routed == "turbo")] | length' "$METRICS_FILE" 2>/dev/null || echo "0")
  if [ "$SMART_ROUTES" -gt 0 ]; then
    FALLBACK_PCT=$((FALLBACKS * 100 / SMART_ROUTES))
    echo "- Smart routes: ${SMART_ROUTES} / Turbo fallbacks: ${FALLBACKS}"
    echo "- Fallback rate: ${FALLBACK_PCT}%"
  else
    echo "- No smart routing data"
  fi
else
  echo "- No metrics data"
fi
echo ""

# --- Summary Table ---
echo "## Summary"
echo ""
echo "| Metric | Value |"
echo "|--------|-------|"

# Re-compute for table
if [ -f "$EVENTS_FILE" ]; then
  SC=$(jq -s '[.[] | select(.event == "task_started")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  CC=$(jq -s '[.[] | select(.event == "task_completed_confirmed")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  GP=$(jq -s '[.[] | select(.event == "gate_passed")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  GF=$(jq -s '[.[] | select(.event == "gate_failed")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  GT=$((GP + GF))
  FR=0
  [ "$GT" -gt 0 ] && FR=$((GF * 100 / GT))
  RJ=$(jq -s '[.[] | select(.event == "task_completion_rejected")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  RS=$(jq -s '[.[] | select(.event == "snapshot_restored" or .event == "state_recovered")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0")
else
  SC=0; CC=0; GP=0; GF=0; GT=0; FR=0; RJ=0; RS=0
fi

if [ -f "$METRICS_FILE" ]; then
  OV=$(jq -s '[.[] | select(.event == "token_overage")] | length' "$METRICS_FILE" 2>/dev/null || echo "0")
  LC=$(jq -s '[.[] | select(.event == "file_conflict")] | length' "$METRICS_FILE" 2>/dev/null || echo "0")
else
  OV=0; LC=0
fi

echo "| Tasks started | ${SC} |"
echo "| Tasks confirmed | ${CC} |"
echo "| Token overages | ${OV} |"
echo "| Gate failure rate | ${FR}% (${GF}/${GT}) |"
echo "| Lease conflicts | ${LC} |"
echo "| Resume successes | ${RS} |"
echo "| Completion rejections | ${RJ} |"
