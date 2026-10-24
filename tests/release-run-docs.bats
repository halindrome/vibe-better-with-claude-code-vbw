#!/usr/bin/env bats
# R152: the guides name the release run, bash tools/test.sh --release, where
# the timed speed checks run: docs/proof.md, CONTRIBUTING.md and the testing
# section of CLAUDE.md. CI runs it on every pull request and is the gate (owner
# decision 2026-10-24); before a push the changed area's test files run
# locally. L1: the files are read as text.

load helper

# flat: stdin on one line, lower case, spaces squeezed.
flat() { tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

# testing_section: the "## Testing" section of CLAUDE.md.
testing_section() {
  awk '/^## Testing/ { on = 1; print; next } on && /^## / { exit } on { print }' "$REPO_ROOT/CLAUDE.md"
}

@test "R152: docs/proof.md and CONTRIBUTING.md name bash tools/test.sh --release" {
  local f
  for f in "$REPO_ROOT/docs/proof.md" "$REPO_ROOT/CONTRIBUTING.md"; do
    flat < "$f" | grep -qF 'tools/test.sh --release' || { echo "$f does not name bash tools/test.sh --release"; false; }
  done
}

@test "R152: the testing section of CLAUDE.md names the release run, makes CI the gate and asks for the changed area's tests before a push" {
  local t
  t=$(testing_section | flat)
  [ -n "$t" ] || { echo "CLAUDE.md has no Testing section"; false; }
  printf '%s' "$t" | grep -qF 'tools/test.sh --release' || { echo "the testing section does not name bash tools/test.sh --release"; false; }
  printf '%s' "$t" | grep -qF 'ci is the gate' || { echo "the testing section does not make CI the gate"; false; }
  printf '%s' "$t" | grep -qF 'before pushing, run the test files of the changed area' || { echo "the testing section does not say what runs before a push"; false; }
}

@test "R152: CONTRIBUTING.md and docs/proof.md say CI runs the release run on every pull request" {
  flat < "$REPO_ROOT/CONTRIBUTING.md" | grep -qF "the pull request's ci is the gate" || { echo "CONTRIBUTING.md"; false; }
  flat < "$REPO_ROOT/docs/proof.md" | grep -qF 'which ci runs on every pull request' || { echo "docs/proof.md"; false; }
}
