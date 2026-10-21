#!/usr/bin/env bats
# R202 (docs/proof.md, D245): the timed proof-speed test, tests/timed-proof-speed.bats,
# runs only in the release run (tools/test.sh --release), never in a proof. It
# builds a scaled-down stand-in with tools/measure-proof-speed.sh --generate
# (about 2,000 files, 300 folders, 40 units), proves it, and fails when the
# proof's own read tracking exceeds 1 s per unit or its planning exceeds 5 s
# (read from evidence.own); a machine too busy to measure is reported as busy
# and skipped, not failed, like the other timed tests. L1: the file's structure
# (the timed file itself costs a minute and runs once per release).

load helper

TIMED="$REPO_ROOT/tests/timed-proof-speed.bats"
TEST_SH="$REPO_ROOT/tools/test.sh"

@test "R202: the timed test exists, is named like the other timed tests, and loads the helper" {
  [ -f "$TIMED" ] || { echo "tests/timed-proof-speed.bats is missing"; false; }
  grep -q '^load helper' "$TIMED"
  grep -q 'tests/timed-\*\.bats' "$TEST_SH"
}

@test "R202: it builds the scaled-down stand-in with the tool's --generate" {
  grep -q 'measure-proof-speed.sh' "$TIMED"
  grep -q -- '--generate' "$TIMED"
  grep -q -- '--files 2000' "$TIMED"
  grep -q -- '--folders 300' "$TIMED"
  grep -q -- '--units 40' "$TIMED"
}

@test "R202: it holds read tracking to 1 s per unit and planning to 5 s, from the evidence" {
  grep -q '^TRACKING_PER_UNIT_LIMIT=1$' "$TIMED"
  grep -q '^PLANNING_LIMIT=5$' "$TIMED"
  grep -q 'evidence.own.tracking' "$TIMED"
  grep -q 'evidence.own.planning' "$TIMED"
}

@test "R202: a machine too busy to measure is reported as busy and skipped" {
  grep -q 'too busy to measure' "$TIMED"
  grep -q 'skip ' "$TIMED"
}
