#!/usr/bin/env bats
# The hermetic helper itself: teardown must succeed in a test that needed no
# project (no vbw_setup), so such tests do not fail after their assertions.

load helper

@test "vbw_teardown succeeds when vbw_setup never ran" {
  unset TEST_ROOT
  run vbw_teardown
  [ "$status" -eq 0 ]
}

# The one macOS teardown failure seen in CI ("rm: Directory not empty" on .git/objects, 2026-10-11) was
# not reproduced and its cause is not proven; a detached gc or maintenance after a commit is the
# candidate, and this setting removes it. If the failure returns, capture ps in teardown.
@test "R172: the helper turns off background git work (gc and maintenance) in the test gitconfig" {
  vbw_setup
  [ "$(git config --global --get gc.auto)" = 0 ]
  [ "$(git config --global --get maintenance.auto)" = false ]
  vbw_teardown
}
