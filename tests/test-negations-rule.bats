#!/usr/bin/env bats
# Testing rule (CLAUDE.md, zero tolerance): no test asserts with a negated
# command that cannot fail it. bash's errexit, which bats relies on, ignores a
# command negated with "!", so "! cmd" fails a test or a helper only as the last
# command of its block; anywhere else it carries its own failure ("! cmd ||
# false"). tools/check-test-negations.sh FILE... names each offending line as
# FILE:LINE and exits 1. The self-tests plant each case in a scratch file. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

rule() { bash "$REPO_ROOT/tools/check-test-negations.sh" "$@"; }

# planted LINE...: a scratch test file holding LINES; prints its path.
planted() {
  local f="$TEST_ROOT/planted.bats"
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

@test "rule: no test file of VBW asserts with a negated command that is not its block's last" {
  cd "$REPO_ROOT"
  run rule tests/*.bats tests/*.bash
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rule self-test: a negated command before the end of a test, of a helper or of a loop body is caught" {
  local f
  f=$(planted '@test "a" {' '  ! grep -q x file' '  true' '}' \
    'helper() {' '  ! grep -q y file' '  true' '}' \
    '@test "b" {' '  for i in 1 2; do' '    ! grep -q "$i" file' '  done' '}' \
    '@test "c" {' '  ! grep -q z \' '    file' '  true' '}')
  run rule "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"planted.bats:2:"* && "$output" == *"planted.bats:6:"* && "$output" == *"planted.bats:11:"* && "$output" == *"planted.bats:15:"* ]] \
    || { echo "$output"; false; }
}

@test "rule self-test: a negated last command, one with its own failure and here-document text pass" {
  local f
  f=$(planted '@test "a" {' '  true' '  ! grep -q x file' '}' \
    '@test "b" {' '  ! grep -q x file || false' '  ! grep -q y file \' '    || { echo y; false; }' '  true' '}' \
    '@test "c" {' "  cat > s.sh << 'SH'" '! grep -q x file' 'echo after' 'SH' '  true' '}' \
    '@test "d" {' '  jq -n . <<< "{}"' '  true' '}')
  run rule "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
