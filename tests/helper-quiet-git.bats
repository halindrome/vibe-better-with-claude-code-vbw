#!/usr/bin/env bats
# R166, R167 (docs/proof.md): a test of this suite never opens the repository
# it is run from. A proof runs each test file in a clean copy of the committed
# code and records a unit as "reads the project through git" when any git
# command opened the copy's repository, so such a unit runs again in every
# proof. The test helper's own git calls (git config --global in vbw_setup)
# therefore run from the test's temporary folder, never from the repository.
# Here a small repository holds a copy of the helper and a one-test file; the
# access times of its HEAD and index are set back, the file runs from inside
# it, and neither may have been read. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R166: a test using vbw_setup and vbw_teardown opens no repository it is run from" {
  local repo="$TEST_ROOT/suite repo" trace="$TEST_ROOT/git.trace" moved
  mkdir -p "$repo/tests"
  cp "$REPO_ROOT/tests/helper.bash" "$repo/tests/helper.bash"
  cat > "$repo/tests/one.bats" << 'BATS'
load helper
setup() { vbw_setup; }
teardown() { vbw_teardown; }
@test "one" { vbw_git_project; [ -f README.md ]; }
BATS
  git -C "$repo" init -q
  git -C "$repo" add -A
  git -C "$repo" -c user.email=t@example.com -c user.name=T commit -q -m "chore(test): suite"
  : > "$TEST_ROOT/ref" && touch -t 200001020000 "$TEST_ROOT/ref"
  touch -a -t 200001010000 "$repo/.git/HEAD" "$repo/.git/index"
  run bash -c 'cd "$1" && GIT_TRACE2_EVENT="$2" bats tests/one.bats' _ "$repo" "$trace"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  moved=$(find "$repo/.git/HEAD" "$repo/.git/index" -maxdepth 0 -anewer "$TEST_ROOT/ref")
  [ -z "$moved" ] || {
    printf 'the test read the repository it ran from:\n%s\ngit commands that opened it:\n' "$moved"
    jq -r --arg w "$repo" 'select(.event == "def_repo" and .worktree == $w) | .sid' "$trace" 2> /dev/null | sort -u | while read -r sid; do
      jq -r --arg s "$sid" 'select(.event == "start" and .sid == $s) | .argv | join(" ")' "$trace" 2> /dev/null | head -n 1
    done
    false
  }
}
