#!/usr/bin/env bats
# The clone's store of recorded runs holds current units only (docs/proof.md,
# "Unit time and the budget per unit"): when vbw prove saves, the runs of units
# that no longer exist leave the store: a deleted test file, a test file an
# approved check now runs, a check taken out of the record. The store is shared
# by the clone's worktrees, so a unit another worktree still has (a check its
# record names, a test file in its folder) keeps its run until that worktree is
# gone. L1.
#
# One proved project with a single-file form is built once for the file and
# copied for each case.

load helper

setup_file() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'grep -q . src/a.txt\n' > tests/c1.sh
  printf 'grep -q . src/a.txt\n' > tests/t_a.sh
  printf 'grep -q . src/a.txt\n' > tests/t_b.sh
  printf 'grep -q . src/a.txt\n' > tests/t_c.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  edit_record '.checks = [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}]
    | .phases = [{id: "P1", title: "Shop", reqs: ["R1"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Shop", reqs: ["R1"], files: ["src/a.txt"], after: [], status: "done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  cp -Rp "$PROJECT" "$BATS_FILE_TMPDIR/project"
  vbw_teardown
}

setup() {
  vbw_setup
  cd "$TEST_ROOT" && rm -rf "$PROJECT"
  cp -Rp "$BATS_FILE_TMPDIR/project" "$PROJECT" && cd "$PROJECT"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

keys() { jq -c '.runs | keys' "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"; }

# change: tests/t_a.sh is deleted, C1 leaves the record and C2 runs tests/t_b.sh; committed and approved.
change() {
  git rm -q tests/t_a.sh
  edit_record '.checks = [{id: "C2", req: "R1", run: ["sh", "tests/t_b.sh"], files: ["tests/t_b.sh"]}]'
  git add -A && git commit -q -m "chore: fewer units"
  "$VBW" approve > /dev/null
}

@test "run store: a proof drops the runs of a deleted test file, of a test file a check now runs and of a removed check" {
  [ "$(keys)" = '["check:C1","file:tests/t_a.sh","file:tests/t_b.sh","file:tests/t_c.sh"]' ] || { keys; false; }
  change
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(keys)" = '["check:C2","file:tests/t_c.sh"]' ] || { keys; false; }
}

@test "run store: a unit another worktree of the clone still has keeps its run until that worktree is gone" {
  git worktree add -q --detach "$TEST_ROOT/other" HEAD
  change
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(keys)" = '["check:C1","check:C2","file:tests/t_a.sh","file:tests/t_b.sh","file:tests/t_c.sh"]' ] || { keys; false; }
  git worktree remove --force "$TEST_ROOT/other"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(keys)" = '["check:C2","file:tests/t_c.sh"]' ] || { keys; false; }
}
