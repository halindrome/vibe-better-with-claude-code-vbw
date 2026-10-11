#!/usr/bin/env bats
# R166, R172 (docs/proof.md): a test of this suite never opens the repository
# it is run from. A proof runs each test file in a clean copy of the committed
# code and records a unit as "reads the project through git" when any git
# command opened the copy's repository, so such a unit runs again in every
# proof. The test helper's own git calls (git config --global in vbw_setup)
# therefore run from the test's temporary folder, never from the repository.
# Here a small repository holds a copy of the helper; the access times of its
# HEAD and index are set back, the helper's setup and teardown run from inside
# it (a plain shell, not a nested bats run: bats inside bats loses a test on
# Linux, found in CI on 2026-10-11), and neither may have been read. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# helper_run HELPER_FILE: set up and tear down a test project with HELPER_FILE
# from inside the repository, tracing every git command; sets REPO and TRACE.
helper_run() {
  REPO="$TEST_ROOT/suite repo"
  TRACE="$TEST_ROOT/git.trace"
  mkdir -p "$REPO/tests"
  cp "$1" "$REPO/tests/helper.bash"
  git -C "$REPO" init -q
  git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@example.com -c user.name=T commit -q -m "chore(test): suite"
  : > "$TEST_ROOT/ref" && touch -t 200001020000 "$TEST_ROOT/ref"
  touch -a -t 200001010000 "$REPO/.git/HEAD" "$REPO/.git/index"
  run env -u TEST_ROOT BATS_TEST_DIRNAME="$REPO/tests" GIT_TRACE2_EVENT="$TRACE" \
    bash -c 'cd "$1" && . tests/helper.bash && vbw_setup && vbw_git_project && vbw_teardown' _ "$REPO"
}

# moved: the repository files a git command read since the reset.
moved() { find "$REPO/.git/HEAD" "$REPO/.git/index" -maxdepth 0 -anewer "$TEST_ROOT/ref"; }

@test "R166: a test using vbw_setup and vbw_teardown opens no repository it is run from" {
  helper_run "$REPO_ROOT/tests/helper.bash"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(moved)" ] || {
    printf 'the helper read the repository it ran from:\n%s\ngit commands that opened it:\n' "$(moved)"
    jq -r --arg w "$REPO" 'select(.event == "def_repo" and .worktree == $w) | .sid' "$TRACE" 2> /dev/null | sort -u | while read -r sid; do
      jq -r --arg s "$sid" 'select(.event == "start" and .sid == $s) | .argv | join(" ")' "$TRACE" 2> /dev/null | head -n 1
    done
    false
  }
}

@test "R172: the check sees a helper that reads the repository: the helper before the fix fails it" {
  # The helper as it was before the fix: the same file without its leading cd into the test folder.
  grep -v '^  cd "\$TEST_ROOT" || return 1$' "$REPO_ROOT/tests/helper.bash" > "$TEST_ROOT/old-helper.bash"
  ! cmp -s "$TEST_ROOT/old-helper.bash" "$REPO_ROOT/tests/helper.bash" || { echo "the helper has no leading cd to remove"; false; }
  helper_run "$TEST_ROOT/old-helper.bash"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -n "$(moved)" ] || { echo "the old helper was not seen reading the repository"; false; }
}
