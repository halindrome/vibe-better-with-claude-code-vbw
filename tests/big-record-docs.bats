#!/usr/bin/env bats
# R149: a record of any size is supported, because record-sized data never
# reaches a helper program as a command-line argument. The behaviour is pinned
# by big-record-hooks.bats and record-args-rule.bats; this file keeps the facts
# the guide rests on. L1.

load helper

@test "R149: docs/record.md exists and the rule's own test file, record-args-rule.bats, is in the suite" {
  [ -f "$REPO_ROOT/docs/record.md" ]
  [ -f "$REPO_ROOT/tests/record-args-rule.bats" ]
}
