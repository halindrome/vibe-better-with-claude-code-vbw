#!/usr/bin/env bats
# R110 (D260): docs/proof.md explains, in plain words, which checks run again
# (a changed definition, a last result that was not a pass, a change to a file
# on its read list), which are reused, and that a check is judged by what it
# read, never by the files it or its plans declare: a check that declares no
# files is reused like any other. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R110: docs/proof.md says which checks run again: a changed read file, a changed definition, a last result that was not a pass" {
  grep -qi 'read list' "$DOC"
  grep -qi 'approved definition' "$DOC"
  grep -qi 'fail, timeout or lost' "$DOC"
  ! grep -qi 'served files' "$DOC" || { grep -ni 'served files' "$DOC"; false; }
  ! grep -qi "files of every plan that serves" "$DOC" || { grep -ni "files of every plan that serves" "$DOC"; false; }
}

@test "R110: docs/proof.md says which checks are reused, and that a reused result keeps the time it really ran" {
  grep -qi 'checks: [0-9N]* ran, [0-9N]* reused' "$DOC"
  grep -qi 'keeps the time' "$DOC"
}

@test "R110: docs/proof.md says a check that declares no files is judged by what it read, and no longer that it always runs" {
  grep -qi 'declares no files' "$DOC"
  ! grep -qi 'declares no files always runs' "$DOC" || { grep -ni 'declares no files always runs' "$DOC"; false; }
  ! grep -qi 'served path' "$DOC" || { grep -ni 'served path' "$DOC"; false; }
}

@test "R110: docs/proof.md says uncommitted changes change nothing, an interrupted proof reuses nothing, and a second proof is fresh" {
  grep -qi 'does not make a check run again' "$DOC"
  grep -qi 'uncommitted' "$DOC"
  grep -qi 'interrupted' "$DOC"
  grep -qi 'second `vbw prove`' "$DOC"
}

@test "R110: docs/proof.md no longer says a changed committed file reruns every check" {
  ! grep -q 'a committed project file differs from the last passing proof' "$DOC"
}
