#!/usr/bin/env bats
# R164 (CLAUDE.md testing, docs/proof.md): bash tools/test.sh
# --release reuses the last proof (recorded in .vbw/record.json) when it passed
# on code that differs from the working tree only in the version files (those
# tools/bump-version.sh writes, listed by its --files) and plugin/CHANGELOG.md
# (T115): it then runs only the timed speed checks
# and the benchmarks, and prints which proof it reused. When any other file
# differs (uncommitted changes included), when there is no passing proof, or
# when the last proof failed, it runs everything and prints why. Which proofs
# count is tests/release-reuse-partial.bats (R170). Failing timed checks or
# benchmarks still fail the run, and the CI shards behave as before. L1: the
# fixture of tests/release-reuse-helper.bash.

load helper
load release-reuse-helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R164: with only the version files and the changelog changed since a passing proof, the release run reuses it" {
  fake_repo
  bump
  fake_run --release
  reused
}

@test "R164: the same holds when the version change is committed" {
  fake_repo
  bump
  (cd "$FAKE" && git add -A && git commit -q -m "chore(release): 1.0.1")
  fake_run --release
  reused
}

@test "R164: any other changed file, committed or not, runs everything and says why" {
  fake_repo
  bump
  printf '# Fake, changed\n' > "$FAKE/README.md"
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
  [[ "$OUT" == *"README.md"* ]] || { echo "the reason does not name README.md: $OUT"; false; }
  (cd "$FAKE" && git add -A && git commit -q -m "docs: readme")
  fake_run --release
  everything
  [[ "$OUT" == *"README.md"* ]] || { echo "the reason does not name README.md: $OUT"; false; }
}

@test "R164: a new untracked file runs everything and says why" {
  fake_repo
  printf 'new\n' > "$FAKE/src/new.txt"
  fake_run --release
  everything
  [[ "$OUT" == *"src/new.txt"* ]] || { echo "the reason does not name src/new.txt: $OUT"; false; }
}

@test "R164: with no proof recorded, the release run runs everything and says why" {
  fake_repo
  jq 'del(.evidence)' "$FAKE/.vbw/record.json" > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" "$FAKE/.vbw/record.json"
  bump
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
  [[ "$OUT" == *"proof"* ]] || { echo "no reason given: $OUT"; false; }
}

@test "R164: when the last proof failed, the release run runs everything and says why" {
  fake_repo
  prove_with '{full: true, passed: false, test_run: {status: "fail", exit: 1, seconds: 900, tail: "not ok"}, commands: {test: {status: "fail", exit: 1, seconds: 900, tail: "not ok"}}}'
  bump
  fake_run --release
  everything
  [[ "$OUT" == *"fail"* ]] || { echo "the reason does not say the proof failed: $OUT"; false; }
}

@test "R164: when the proof is reused, a failing benchmark or timed check still fails the run" {
  fake_repo
  bump
  FAIL=bench-hooks fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
  FAIL=bench-panel fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
  FAIL=timed fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
}

@test "R164: the CI shards run their whole share whatever proof is recorded" {
  fake_repo
  bump
  fake_run --shard 1/1
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
}
