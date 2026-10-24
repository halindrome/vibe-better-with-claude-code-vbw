#!/usr/bin/env bats
# T172 (docs/proof.md, "Cores per unit"): a unit's command gets its share of the
# processor cores through the variables build tools read: CARGO_BUILD_JOBS,
# GOMAXPROCS and MAKEFLAGS (-jN). The share is the cores divided by the units this
# run puts side by side (check_jobs, under the computer-wide limit; at least 1);
# an alone check gets every core. A variable the user's environment already sets
# is left as it is. L1: faked core counts (machine-helper), a check that prints
# what it received.

load helper
load machine-helper

setup() {
  machine_setup
  # tests/env.sh NAME appends "NAME cargo=.. go=.. make=.." to $TEST_ROOT/env.log.
  mkdir -p "$PROJECT/tests"
  printf '%s\n' 'printf "%s cargo=%s go=%s make=%s\n" "$1" "${CARGO_BUILD_JOBS-unset}" "${GOMAXPROCS-unset}" "${MAKEFLAGS-unset}" >> "$TEST_ROOT/env.log"' > "$PROJECT/tests/env.sh"
  # C1 and C2 print what they received; C3 does too and runs alone.
  machine_project "$PROJECT" A 0 0 '[{"id": "C1", "req": "R1", "run": ["sh", "tests/env.sh", "C1"], "files": ["tests/env.sh"]},
    {"id": "C2", "req": "R1", "run": ["sh", "tests/env.sh", "C2"], "files": ["tests/env.sh"]},
    {"id": "C3", "req": "R1", "run": ["sh", "tests/env.sh", "C3"], "files": ["tests/env.sh"], "alone": true}]'
  cd "$PROJECT"
}
teardown() { machine_teardown; }

@test "T172: each unit gets cores divided by the units side by side, an alone check every core" {
  cores 8
  "$VBW" config set check_jobs 2 > /dev/null
  run "$VBW" check C1 C2 C3 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'C1 cargo=4 go=4 make=-j4' "$TEST_ROOT/env.log" || { cat "$TEST_ROOT/env.log"; false; }
  grep -qx 'C2 cargo=4 go=4 make=-j4' "$TEST_ROOT/env.log" || { cat "$TEST_ROOT/env.log"; false; }
  grep -qx 'C3 cargo=8 go=8 make=-j8' "$TEST_ROOT/env.log" || { cat "$TEST_ROOT/env.log"; false; }
}

@test "T172: the computer-wide limit counts: 2 cores with check_jobs 4 run one unit at a time on both cores; a variable the environment sets is left as it is" {
  cores 2
  "$VBW" config set check_jobs 4 > /dev/null
  CARGO_BUILD_JOBS=16 run "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'C1 cargo=16 go=2 make=-j2' "$TEST_ROOT/env.log" || { cat "$TEST_ROOT/env.log"; false; }
}

@test "T172: an unreadable core count sets nothing" {
  cores none
  run "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'C1 cargo=unset go=unset make=unset' "$TEST_ROOT/env.log" || { cat "$TEST_ROOT/env.log"; false; }
}

@test "T172: docs/proof.md describes cores per unit, and the fixed known issue is gone" {
  local t
  t=$(tr '\n' ' ' < "$REPO_ROOT/docs/proof.md" | tr -s ' ')
  [[ "$t" == *"#### Cores per unit"* && "$t" == *'`CARGO_BUILD_JOBS`, `GOMAXPROCS` and `MAKEFLAGS` (`-jN`)'* ]] || { echo "docs/proof.md"; false; }
  [[ "$t" == *"A variable your environment already sets is passed on unchanged"* ]] || { echo "docs/proof.md: own settings"; false; }
  ! grep -qF 'Heavy checks each use every core' "$REPO_ROOT/docs/known-issues.md" || { echo "the fixed entry is still listed"; false; }
}
