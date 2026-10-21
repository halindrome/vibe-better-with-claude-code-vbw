#!/usr/bin/env bats
# R110 (D260): docs/proof.md names the read list, the statuses that make a
# check run again (fail, timeout or lost) and the count line; the old served
# files rule and the claims that a check declaring no files always runs or a
# changed committed file reruns every check are gone. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R110: docs/proof.md names the read list and the statuses that make a check run again" {
  grep -qi 'read list' "$DOC"
  grep -qi 'fail, timeout or lost' "$DOC"
  ! grep -qi 'served files' "$DOC" || { grep -ni 'served files' "$DOC"; false; }
  ! grep -qi "files of every plan that serves" "$DOC" || { grep -ni "files of every plan that serves" "$DOC"; false; }
}

@test "R110: docs/proof.md shows the checks count line" {
  grep -qi 'checks: [0-9N]* ran, [0-9N]* reused' "$DOC"
}

@test "R110: docs/proof.md no longer says a check that declares no files always runs" {
  ! grep -qi 'declares no files always runs' "$DOC" || { grep -ni 'declares no files always runs' "$DOC"; false; }
  ! grep -qi 'served path' "$DOC" || { grep -ni 'served path' "$DOC"; false; }
}

@test "R110: docs/proof.md no longer says a changed committed file reruns every check" {
  ! grep -q 'a committed project file differs from the last passing proof' "$DOC"
}
