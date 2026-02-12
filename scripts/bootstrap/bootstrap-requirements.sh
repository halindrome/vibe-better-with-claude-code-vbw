#!/usr/bin/env bash
set -euo pipefail

# bootstrap-requirements.sh — Generate REQUIREMENTS.md from discovery data
#
# Usage: bootstrap-requirements.sh OUTPUT_PATH DISCOVERY_JSON_PATH
#   OUTPUT_PATH          Path to write REQUIREMENTS.md
#   DISCOVERY_JSON_PATH  Path to discovery.json with answered[] and inferred[]

if [[ $# -lt 2 ]]; then
  echo "Usage: bootstrap-requirements.sh OUTPUT_PATH DISCOVERY_JSON_PATH" >&2
  exit 1
fi

OUTPUT_PATH="$1"
DISCOVERY_JSON="$2"

if [[ ! -f "$DISCOVERY_JSON" ]]; then
  echo "Error: Discovery file not found: $DISCOVERY_JSON" >&2
  exit 1
fi

# Validate JSON
if ! jq empty "$DISCOVERY_JSON" 2>/dev/null; then
  echo "Error: Invalid JSON in $DISCOVERY_JSON" >&2
  exit 1
fi

CREATED=$(date +%Y-%m-%d)

# Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Extract data from discovery.json
ANSWERED_COUNT=$(jq '.answered | length' "$DISCOVERY_JSON")
INFERRED_COUNT=$(jq '.inferred | length' "$DISCOVERY_JSON")

# Start building the file
{
  echo "# Requirements"
  echo ""
  echo "Defined: ${CREATED}"
  echo ""
  echo "## Problem Statement"
  echo ""
  echo "_(To be defined during discovery)_"
  echo ""
  echo "## Requirements"
  echo ""

  # Generate requirements from inferred data
  if [[ "$INFERRED_COUNT" -gt 0 ]]; then
    REQ_NUM=1
    for i in $(seq 0 $((INFERRED_COUNT - 1))); do
      REQ_ID=$(printf "REQ-%02d" "$REQ_NUM")
      REQ_TEXT=$(jq -r ".inferred[$i].text // .inferred[$i]" "$DISCOVERY_JSON")
      REQ_PRIORITY=$(jq -r ".inferred[$i].priority // \"Must-have\"" "$DISCOVERY_JSON")
      echo "### ${REQ_ID}: ${REQ_TEXT}"
      echo "**${REQ_PRIORITY}**"
      echo ""
      REQ_NUM=$((REQ_NUM + 1))
    done
  else
    echo "_(No requirements defined yet)_"
    echo ""
  fi

  echo "## Out of Scope"
  echo ""
  echo "_(To be defined)_"
} > "$OUTPUT_PATH"

exit 0
