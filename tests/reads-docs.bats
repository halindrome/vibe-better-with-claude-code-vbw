#!/usr/bin/env bats
# R166: docs/proof.md explains in plain words when a check's result is reused
# (its read list: the files it opened and the folders it listed while it ran),
# where read lists are kept (vbw/runs.json in the clone's git directory, never
# in the record), and the limits: what lies outside the project (installed
# tools, the network, the clock) is not tracked, and vbw prove --full or a
# second proof with nothing committed (D173) runs everything fresh. The old
# served-files and documentation-only rules are gone from it. Read lists add
# no runtime dependency (no tracing tool), and the guards and the status line
# never read them, so their cost does not grow with them. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R166: docs/proof.md says what a read list is and that it comes from the run itself" {
  grep -qi 'read list' "$DOC"
  grep -qiE 'opened|opens' "$DOC"
  grep -qiE 'listed|lists' "$DOC"
  grep -qi 'never from file names' "$DOC"
}

@test "R166: docs/proof.md says when a result is reused and when the check runs again" {
  grep -qi 'approved definition' "$DOC"
  grep -qiE 'changed, deleted or renamed' "$DOC"
  grep -qiE 'added to or removed from a folder' "$DOC"
  grep -qi 'last result failed' "$DOC"
  grep -qi 'never passed' "$DOC"
  grep -qi 'no read list' "$DOC"
}

@test "R166: docs/proof.md names where read lists are kept" {
  grep -qF 'vbw/runs.json' "$DOC"
}

@test "R166: docs/proof.md names the limits and how to run everything fresh" {
  grep -qi 'installed tools' "$DOC"
  grep -qi 'network' "$DOC"
  grep -qi 'clock' "$DOC"
  grep -qF 'vbw prove --full' "$DOC"
  grep -qi 'nothing committed' "$DOC"
}

@test "R166: docs/proof.md says that QA and shipping accept a proof that reused results" {
  grep -qiE '(QA|vbw qa record).*(accept|take).*reused|reused.*(QA|vbw qa record).*(accept|take)' "$DOC"
}

@test "R166: docs/proof.md no longer describes the served-files rule, the passes cache or the documentation-only rule" {
  ! grep -qi 'served files are' "$DOC" || { echo "the served-files rule is still described"; false; }
  ! grep -qF 'vbw/passes.json' "$DOC" || { echo "the passes cache is still described"; false; }
  ! grep -qi 'only documentation changed since' "$DOC" || { echo "the documentation-only rule is still described"; false; }
}

@test "R166: recording read lists adds no tracing tool as a runtime dependency" {
  run grep -rnwE 'strace|dtruss|dtrace|fs_usage|opensnoop|inotifywait|fswatch|ltrace|lsof|fatrace|auditctl' "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/bin"
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R166: the guards and the status line never read the read lists" {
  run grep -rnF 'runs.json' "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/lib/cmd-statusline.sh"
  [ -z "$output" ] || { echo "$output"; false; }
  grep -rqF 'runs.json' "$PLUGIN_ROOT/lib"
}
