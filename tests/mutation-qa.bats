#!/usr/bin/env bats
# R188 (P141): the QA agent reads the mutation check's results with vbw show
# plan. L1: the text of plugin/agents/qa.md.

load helper

QA="$PLUGIN_ROOT/agents/qa.md"

# has_line WORD...: one line of qa.md holds every WORD (case-insensitive).
has_line() {
  local lines w
  lines=$(cat "$QA")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of qa.md holds all of: $*"; return 1; }; done
}

@test "R188: QA reads the recorded mutation results with vbw show plan" {
  has_line mutation "vbw show plan"
}
