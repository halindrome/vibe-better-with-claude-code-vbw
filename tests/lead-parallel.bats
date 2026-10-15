#!/usr/bin/env bats
# R102 (L1, the Lead's part): the Lead orders plans that must share a file into
# separate waves with `after`, and reads the contract's build waves line to see
# the result. The splitting itself is judged by the plans it writes, not by the
# brief's sentences.

load helper

LEAD="$PLUGIN_ROOT/agents/lead.md"

@test "R102: the Lead brief names after and the contract's build waves line" {
  grep -qF '`after`' "$LEAD"
  grep -q 'build waves' "$LEAD"
}
