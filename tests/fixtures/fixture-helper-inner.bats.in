#!/usr/bin/env bats
# Run by tests/fixture-helper.bats ("the build runs once per file, even with bats --jobs 4"),
# copied next to helper.bash and fixture-helper.bash in a scratch folder; never run on its own.
load helper
load fixture-helper
counted() { vbw_setup; vbw_git_project; printf '%s\n' "$1" > variant; printf '%s\n' "$1" >> "$COUNT"; }
setup_file() { fixture_build one counted one; fixture_build two counted two; }
setup() { fixture_copy one; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }
# in_flight: wait (up to 20 s) until another test has started and not ended, so the tests overlap.
in_flight() {
  local i=0 f
  : > "$SYNC/start.$BATS_TEST_NUMBER"
  while [ "$i" -lt 200 ]; do
    for f in "$SYNC"/start.*; do
      [ "$f" = "$SYNC/start.$BATS_TEST_NUMBER" ] || [ -e "$SYNC/end.${f##*.}" ] || { echo overlap >> "$SYNC/overlaps"; return 0; }
    done
    sleep 0.1; i=$((i + 1))
  done
}
mine() {
  in_flight
  [ ! -e mine ] && [ "$(git rev-list --count HEAD)" = 1 ] && [ "$(cat variant)" = "$1" ]
  : > mine; git add mine; git commit -q -m mine
  printf '%s %s\n' "$1" "$TEST_ROOT" >> "$SYNC/roots"
  : > "$SYNC/end.$BATS_TEST_NUMBER"
}
@test "a1" {
  mine one;
}
@test "a2" {
  mine one;
}
@test "a3" {
  mine one;
}
@test "a4" {
  mine one;
}
@test "b1" {
  fixture_copy two; mine two;
}
@test "b2" {
  fixture_copy two; mine two;
}
@test "b3" {
  fixture_copy two; mine two;
}
@test "b4" {
  fixture_copy two; mine two;
}
