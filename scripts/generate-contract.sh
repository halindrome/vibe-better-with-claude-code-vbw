#!/usr/bin/env bash
set -u

# generate-contract.sh <plan-path>
# Generates a contract sidecar JSON from PLAN.md metadata.
# Output: .vbw-planning/.contracts/{phase}-{plan}.json
# Fail-open: exit 0 on any error. Contract generation must never block execution.

if [ $# -lt 1 ]; then
  echo "Usage: generate-contract.sh <plan-path>" >&2
  exit 0
fi

PLAN_PATH="$1"
[ ! -f "$PLAN_PATH" ] && exit 0

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"

# Check feature flag
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  ENABLED=$(jq -r '.v3_contract_lite // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
  [ "$ENABLED" != "true" ] && exit 0
fi

# Extract phase and plan from frontmatter
PHASE=$(awk '/^---$/{n++; next} n==1 && /^phase:/{print $2; exit}' "$PLAN_PATH" 2>/dev/null) || exit 0
PLAN=$(awk '/^---$/{n++; next} n==1 && /^plan:/{print $2; exit}' "$PLAN_PATH" 2>/dev/null) || exit 0
[ -z "$PHASE" ] || [ -z "$PLAN" ] && exit 0

# Extract must_haves from frontmatter
MUST_HAVES=$(awk '
  BEGIN { in_front=0; in_mh=0 }
  /^---$/ { if (in_front==0) { in_front=1; next } else { exit } }
  in_front && /^must_haves:/ { in_mh=1; next }
  in_front && in_mh && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    gsub(/^"/, ""); gsub(/"$/, "")
    print
    next
  }
  in_front && in_mh && /^[^[:space:]]/ { exit }
' "$PLAN_PATH" 2>/dev/null) || true

# Extract file paths from **Files:** lines in task descriptions
ALLOWED_PATHS=$(grep -oE '\*\*Files:\*\* .+' "$PLAN_PATH" 2>/dev/null | \
  sed 's/\*\*Files:\*\* //' | \
  tr ',' '\n' | \
  sed 's/^ *//;s/ *$//;s/ *(new)//;s/ *(if exists)//' | \
  grep -v '^$' | \
  sed 's/^`//;s/`$//' | \
  sort -u) || true

# Count tasks from ### Task N: headings
TASK_COUNT=$(grep -c '^### Task [0-9]' "$PLAN_PATH" 2>/dev/null) || TASK_COUNT=0

# Build JSON arrays
MH_JSON="[]"
if [ -n "$MUST_HAVES" ]; then
  MH_JSON=$(echo "$MUST_HAVES" | jq -R '.' | jq -s '.' 2>/dev/null) || MH_JSON="[]"
fi

AP_JSON="[]"
if [ -n "$ALLOWED_PATHS" ]; then
  AP_JSON=$(echo "$ALLOWED_PATHS" | jq -R '.' | jq -s '.' 2>/dev/null) || AP_JSON="[]"
fi

# Write contract
CONTRACT_DIR="${PLANNING_DIR}/.contracts"
mkdir -p "$CONTRACT_DIR" 2>/dev/null || exit 0

CONTRACT_FILE="${CONTRACT_DIR}/${PHASE}-${PLAN}.json"
jq -n \
  --argjson phase "$PHASE" \
  --argjson plan "$PLAN" \
  --argjson task_count "$TASK_COUNT" \
  --argjson must_haves "$MH_JSON" \
  --argjson allowed_paths "$AP_JSON" \
  '{phase: $phase, plan: $plan, task_count: $task_count, must_haves: $must_haves, allowed_paths: $allowed_paths}' \
  > "$CONTRACT_FILE" 2>/dev/null || exit 0

echo "$CONTRACT_FILE"
