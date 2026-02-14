#!/usr/bin/env bash
set -euo pipefail

# verify-plugin-root-resolution.sh — Ensure CLAUDE_PLUGIN_ROOT is resolvable in all commands
#
# Problem: ${CLAUDE_PLUGIN_ROOT} is available in Claude Code's process env (for !` backtick
# and @ file references) but NOT in the Bash tool's shell environment. Commands that
# reference ${CLAUDE_PLUGIN_ROOT} in regular code blocks (model-executed bash) must expose
# the resolved path via a !` backtick preamble so the model can see the actual path.
#
# Rule: Any command .md file that references ${CLAUDE_PLUGIN_ROOT} outside of safe contexts
# (!` backtick expressions or @ file references) MUST contain a Plugin root preamble:
#   Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT}``
#
# Safe contexts (no preamble needed):
#   - !`...${CLAUDE_PLUGIN_ROOT}...`       (executed at command load time)
#   - @${CLAUDE_PLUGIN_ROOT}/...           (file inclusion at load time)
#
# Unsafe contexts (preamble required):
#   - bash ${CLAUDE_PLUGIN_ROOT}/scripts/... (in regular code blocks)
#   - Read ${CLAUDE_PLUGIN_ROOT}/...         (model instruction text)
#   - ${CLAUDE_PLUGIN_ROOT}/VERSION          (file path in narrative)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

echo "=== Plugin Root Resolution Verification ==="

for file in "$COMMANDS_DIR"/*.md; do
  base="$(basename "$file" .md)"

  # Skip files with no CLAUDE_PLUGIN_ROOT references at all
  if ! grep -q 'CLAUDE_PLUGIN_ROOT' "$file"; then
    pass "$base: no CLAUDE_PLUGIN_ROOT references"
    continue
  fi

  # Count total references
  total_refs=$(grep -c 'CLAUDE_PLUGIN_ROOT' "$file" || true)

  # Count lines with CLAUDE_PLUGIN_ROOT that are NOT in any safe context.
  # A line is safe if it matches: !` backtick expression, @ file reference, or the preamble itself.
  # We pipeline grep to filter out safe lines, then count what remains.
  unsafe_count=$(grep 'CLAUDE_PLUGIN_ROOT' "$file" \
    | grep -v '!`[^`]*CLAUDE_PLUGIN_ROOT' \
    | grep -v '@${CLAUDE_PLUGIN_ROOT}' \
    | grep -vc '`!`echo \${CLAUDE_PLUGIN_ROOT}`' || true)

  # If no unsafe references, no preamble needed
  if [ "$unsafe_count" -eq 0 ]; then
    pass "$base: all $total_refs references are in safe contexts (! backtick or @ file ref)"
    continue
  fi

  # There are unsafe references — check for the preamble
  if grep -q '!`echo \${CLAUDE_PLUGIN_ROOT}`' "$file"; then
    pass "$base: has Plugin root preamble ($unsafe_count model-executed refs resolved)"
  else
    fail "$base: $unsafe_count CLAUDE_PLUGIN_ROOT refs in model-executed context but no Plugin root preamble"
    echo "      Add to Context section: Plugin root: \`!\`echo \${CLAUDE_PLUGIN_ROOT}\`\`"
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All plugin root resolution checks passed."
exit 0
