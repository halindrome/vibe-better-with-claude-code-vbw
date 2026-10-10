#!/usr/bin/env bats
# R152: the guides say where the timed speed checks run. docs/proof.md and the
# testing section of CLAUDE.md say they run in the release run (bash
# tools/test.sh --release: CI and the local run before a push) and that vbw
# prove does not run them; CLAUDE.md and CONTRIBUTING.md name the release run
# as the local run before a push. L1: the files are read as text.

load helper

# flat: stdin on one line, lower case, spaces squeezed.
flat() { tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

# testing_section: the "## Testing" section of CLAUDE.md.
testing_section() {
  awk '/^## Testing/ { on = 1; print; next } on && /^## / { exit } on { print }' "$REPO_ROOT/CLAUDE.md"
}

# not_in_prove TEXT: TEXT says the timed speed checks do not run in vbw prove.
not_in_prove() {
  printf '%s' "$1" | grep -qE '(timed|timing|speed)[^.]*(not|never)[^.]*vbw prove|vbw prove[^.]*(not|never)[^.]*(timed|timing|speed)'
}

# push_sentence TEXT: a sentence of TEXT about the run before a push names --release.
push_sentence() {
  printf '%s' "$1" | tr '.' '\n' | grep -E 'push' | grep -q -- '--release'
}

@test "R152: docs/proof.md says the timed speed checks run in the release run and vbw prove does not run them" {
  local t
  t=$(flat < "$REPO_ROOT/docs/proof.md")
  printf '%s' "$t" | grep -qF 'tools/test.sh --release' || {
    echo "docs/proof.md does not name bash tools/test.sh --release"
    false
  }
  not_in_prove "$t" || {
    echo "docs/proof.md does not say vbw prove does not run the timed speed checks"
    false
  }
}

@test "R152: the testing section of CLAUDE.md names the release run, says vbw prove does not run the timed checks, and runs it before a push" {
  local t
  t=$(testing_section | flat)
  [ -n "$t" ] || {
    echo "CLAUDE.md has no Testing section"
    false
  }
  printf '%s' "$t" | grep -qF 'tools/test.sh --release' || {
    echo "the testing section does not name bash tools/test.sh --release"
    false
  }
  not_in_prove "$t" || {
    echo "the testing section does not say vbw prove does not run the timed speed checks"
    false
  }
  push_sentence "$t" || {
    echo "the testing section's run before a push is not the release run"
    false
  }
}

@test "R152: CONTRIBUTING.md names the release run as the local run before a push" {
  local t
  t=$(flat < "$REPO_ROOT/CONTRIBUTING.md")
  printf '%s' "$t" | grep -qF 'tools/test.sh --release' || {
    echo "CONTRIBUTING.md does not name bash tools/test.sh --release"
    false
  }
  push_sentence "$t" || {
    echo "CONTRIBUTING.md's run before a push is not the release run"
    false
  }
}
