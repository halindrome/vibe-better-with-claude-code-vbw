#!/usr/bin/env bats
# R188 (P141): the QA agent reads the mutation check's results. Its
# specification says, on its test-gap rule, that the breaks recorded for a plan
# (vbw show plan: red, survivor, strengthened check files) are evidence for that
# rule, so QA reads them rather than finding the same gaps again; it stays
# within 900 words. L1: the text of plugin/agents/qa.md.

load helper

QA="$PLUGIN_ROOT/agents/qa.md"

# has_line WORD...: one line of qa.md holds every WORD (case-insensitive).
has_line() {
  local lines w
  lines=$(cat "$QA")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of qa.md holds all of: $*"; return 1; }; done
}

@test "R188: QA's test-gap rule takes the recorded mutation results as evidence and reads them in vbw show plan" {
  has_line "test gap" mutation evidence
  has_line mutation "vbw show plan"
}

@test "R188: QA does not find again a gap a mutation check already recorded" {
  has_line mutation survivor again
}

@test "R188: the QA agent stays within 900 words" {
  [ "$(wc -w < "$QA")" -le 900 ] || { echo "qa.md: $(wc -w < "$QA") words"; false; }
}
