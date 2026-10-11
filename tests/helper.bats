#!/usr/bin/env bats
# The hermetic helper itself: teardown must succeed in a test that needed no
# project (no vbw_setup), so such tests do not fail after their assertions.

load helper

@test "vbw_teardown succeeds when vbw_setup never ran" {
  unset TEST_ROOT
  run vbw_teardown
  [ "$status" -eq 0 ]
}

@test "R172: the helper turns off background git work, so teardown never races a detached gc or maintenance" {
  vbw_setup
  [ "$(git config --global --get gc.auto)" = 0 ]
  [ "$(git config --global --get maintenance.auto)" = false ]
  vbw_teardown
}
