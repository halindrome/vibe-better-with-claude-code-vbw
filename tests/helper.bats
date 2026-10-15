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

# T82: the first test of a file builds the seed repository and every later test copies it.
# A copy must be the repository a build gives: same config, commit and clean index stats.
@test "T82: vbw_git_project copies the file's seed repository, identical to a fresh build" {
  vbw_setup
  vbw_git_project
  [ -f "$BATS_FILE_TMPDIR/vbw-seed/ready" ]
  vbw_teardown
  vbw_setup
  vbw_git_project
  [ "$(git rev-parse HEAD)" = "$(git -C "$BATS_FILE_TMPDIR/vbw-seed/repo" rev-parse HEAD)" ]
  [ "$(git log --format='%an <%ae> %s')" = "VBW Test <test@example.com> chore(test): seed" ]
  [ "$(git symbolic-ref HEAD)" = refs/heads/main ]
  [ "$(cat README.md)" = seed ]
  # The index stats match the copied file: plumbing that trusts them sees no change
  # (checked before any porcelain command refreshes the index).
  git diff-files --quiet
  [ -z "$(git status --porcelain)" ]
  cmp "$GIT_CONFIG_GLOBAL" "$BATS_FILE_TMPDIR/vbw-gitconfig"
  [ "$(git config --global --get gc.auto)" = 0 ]
  vbw_teardown
}

@test "T82: a test that changed what git writes gets a freshly built repository" {
  vbw_setup
  vbw_git_project
  local seeded
  seeded=$(git rev-parse HEAD)
  vbw_teardown
  vbw_setup
  git config --global user.name "Other Name"
  vbw_git_project
  [ "$(git log --format=%an)" = "Other Name" ]
  vbw_teardown
  vbw_setup
  GIT_AUTHOR_NAME="Env Name" vbw_git_project
  [ "$(git log --format=%an)" = "Env Name" ]
  vbw_teardown
  vbw_setup
  git init -q
  printf 'x\n' > x.txt && git add x.txt && git commit -q -m "chore: first"
  vbw_git_project
  [ "$(git rev-list --count HEAD)" = 2 ]
  [ "$(git rev-parse HEAD)" != "$seeded" ]
  vbw_teardown
}
