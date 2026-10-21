#!/usr/bin/env bats
# R170 (CLAUDE.md testing, docs/proof.md): which proofs the release run may
# reuse. A proof that reused earlier results counts: a reused result is one the
# read lists still vouch for, so the proof covers the code as a fresh run would.
# A proof is not reused when a project command was skipped as not approved, or
# when the quick command stood in for the test command: then the release run
# runs everything and says why. L1: the fixture of tests/release-reuse-helper.bash.

load helper
load release-reuse-helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R170: a passing proof that reused results is reused by the release run" {
  fake_repo
  prove_with '{full: false, passed: true, checks: {C1: {status: "pass", exit: 0, seconds: 1, reused: true, at: "2026-10-10T09:00:00Z"}}}'
  bump
  fake_run --release
  reused
}

@test "R170: a proof that skipped a command not yet approved is not reused, and the reason says so" {
  fake_repo
  prove_with '{full: false, passed: true, commands: {test: {status: "pass", exit: 0, seconds: 900, tail: "ok"}, lint: {status: "skipped"}}}'
  bump
  fake_run --release
  everything
  [[ "$OUT" == *"skipped a command"* ]] || { echo "the reason does not name the skipped command: $OUT"; false; }
}

@test "R170: a proof where the quick command stood in for the test command is not reused, and the reason says so" {
  fake_repo
  prove_with '{full: false, passed: true, commands: {quick: {status: "pass", exit: 0, seconds: 60, tail: "ok"}}}'
  bump
  fake_run --release
  everything
  [[ "$OUT" == *"quick command stood in"* ]] || { echo "the reason does not name the quick command: $OUT"; false; }
}
