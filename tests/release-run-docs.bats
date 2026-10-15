#!/usr/bin/env bats
# R152: the guides name the release run, bash tools/test.sh --release, where
# the timed speed checks run: docs/proof.md, CONTRIBUTING.md and the testing
# section of CLAUDE.md, whose rule runs it before a push. L1: the files are
# read as text.

load helper

# flat: stdin on one line, lower case, spaces squeezed.
flat() { tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

# testing_section: the "## Testing" section of CLAUDE.md.
testing_section() {
  awk '/^## Testing/ { on = 1; print; next } on && /^## / { exit } on { print }' "$REPO_ROOT/CLAUDE.md"
}

# push_sentence TEXT: a sentence of TEXT about the run before a push names --release.
push_sentence() {
  printf '%s' "$1" | tr '.' '\n' | grep -E 'push' | grep -q -- '--release'
}

@test "R152: docs/proof.md and CONTRIBUTING.md name bash tools/test.sh --release" {
  local f
  for f in "$REPO_ROOT/docs/proof.md" "$REPO_ROOT/CONTRIBUTING.md"; do
    flat < "$f" | grep -qF 'tools/test.sh --release' || { echo "$f does not name bash tools/test.sh --release"; false; }
  done
}

@test "R152: the testing section of CLAUDE.md runs tools/test.sh --release before a push" {
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
  push_sentence "$t" || {
    echo "the testing section's run before a push is not the release run"
    false
  }
}
