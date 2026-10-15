#!/usr/bin/env bats
# R166: docs/proof.md names the read list, where read lists are kept
# (vbw/runs.json in the clone's git directory), what is not tracked (installed
# tools, the network, the clock) and vbw prove --full. The old served-files and
# documentation-only rules are gone from it. Read lists add
# no runtime dependency (no tracing tool), and the guards and the status line
# never read them, so their cost does not grow with them. L1.

load helper
load protected-helper
load glance-helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

DOC="$REPO_ROOT/docs/proof.md"

@test "R166: docs/proof.md names the read list" {
  grep -qi 'read list' "$DOC"
}

@test "R166: docs/proof.md names where read lists are kept" {
  grep -qF 'vbw/runs.json' "$DOC"
}

@test "R166: docs/proof.md names the limits and how to run everything fresh" {
  grep -qi 'installed tools' "$DOC"
  grep -qi 'network' "$DOC"
  grep -qi 'clock' "$DOC"
  grep -qF 'vbw prove --full' "$DOC"
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
  # The jq guards may name vbw/runs.json (the refusal of a write to it and its
  # pattern), but a jq program opens no file by itself: only its command line
  # (hooks.json) or a script can hand it one. None of them names the store, nor
  # do the status line and the JavaScript hook modules.
  run grep -rnF 'runs.json' "$PLUGIN_ROOT/hooks/hooks.json" "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/lib/cmd-statusline.sh"
  [ -z "$output" ] || { echo "$output"; false; }
  run grep -rnF --exclude='*.jq' 'runs.json' "$PLUGIN_ROOT/hooks"
  [ -z "$output" ] || { echo "$output"; false; }
  grep -rqF 'runs.json' "$PLUGIN_ROOT/lib"
}

@test "R166: the guards never open the store of recorded runs, even when they refuse a write to it" {
  local store a
  glance_project
  store="$PROJECT/.git/vbw/runs.json"
  mkdir -p "${store%/*}"
  printf '{}\n' > "$store"
  touch -a -t 200001010000 "$store"
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write .git/vbw/runs.json workflow-subagent)")
  denied_with "vbw/runs.json"
  ANSWER=$(hook_answer "$PROJECT" "$(bash_in 'echo {} > .git/vbw/runs.json' workflow-subagent)")
  denied_with "vbw/runs.json"
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Read src/a.txt workflow-subagent)")
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"}}' \
    | NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" > /dev/null
  a=$(stat -c %X "$store" 2> /dev/null || stat -f %a "$store")
  [ "$a" -lt 978307200 ] || { echo "a guard or the status line read $store"; false; }
  # The yardstick works here: reading the store moves its access time.
  cat "$store" > /dev/null
  a=$(stat -c %X "$store" 2> /dev/null || stat -f %a "$store")
  [ "$a" -ge 978307200 ] || { echo "this file system does not record reads, so the test proves nothing here"; false; }
}
