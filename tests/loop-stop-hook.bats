#!/usr/bin/env bats
# T150, T147 (D399): the Stop hook that drives a loop and an autonomous run is
# the plugin's own, declared once in hooks.json, never in a skill. A skill's
# hook exists only while the skill is loaded, so after a resumed session no
# loop moved (2026-10-14 21:05: an hour at approve); with /vbw:vibe and
# /vbw:loop both loaded it ran twice, and the loop opened one item twice
# (2026-10-14 17:58). The hook is inert unless this session has a loop on or an
# armed autonomous run in this project: vbw loop start leaves a mark for its
# session (again when the loop is already on for that session, the way back
# after a resume), the loop's end removes it. L1: hooks.json run as Claude Code
# runs it (vbw_hook).

load helper
load loop-helper
load fixture-helper

setup_file() { fixture_build loop loop_project; }
setup() { fixture_copy loop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

stop() { jq -nc --arg s "$1" '{hook_event_name: "Stop", session_id: $s, stop_hook_active: false}' | vbw_hook Stop; }

@test "T150: one Stop hook, the plugin's own, and no skill declares one" {
  jq -e '(.hooks.Stop | length) == 1 and (.hooks.Stop[0].hooks | length) == 1
    and (.hooks.Stop[0].hooks[0].command | test("hooks/stop.sh"))' "$PLUGIN_ROOT/hooks/hooks.json"
  ! grep -lE '^hooks:' "$PLUGIN_ROOT"/skills/*/SKILL.md
}

@test "T150: the hook gives the loop's next step to the loop's session, and nothing to another" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  run stop s1
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "block" and (.reason | test("T1"))' || { echo "$output"; false; }
  run stop s2
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "T150: in a session started in a subfolder of the project the hook drives the loop too" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  mkdir -p "Sub Folder With Spaces"
  HOOK_PROJECT_DIR="$PROJECT/Sub Folder With Spaces" run stop s1
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "block" and (.reason | test("T1"))' || { echo "$output"; false; }
}

@test "T147: one Stop event moves the loop one step: the item opens once" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  stop s1 > /dev/null
  [ "$(git log --format=%s | grep -c '^chore(vbw): loop T1 open$')" -eq 1 ]
}

@test "T150: after a resume the loop is driven again: vbw loop start of the same session restores its mark" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  rm -f .vbw/runtime/loop.s1
  run stop s1
  [ -z "$output" ]
  run env VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling
  [ "$status" -ne 0 ] && [[ "$output" == *"already on"* ]]
  run stop s1
  printf '%s' "$output" | jq -e '.decision == "block"' || { echo "$output"; false; }
}

@test "T150: the loop's end removes its mark, and the hook is silent again" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop stop > /dev/null
  stop s1 > /dev/null || true
  jq -e '.loop.ended != null' .vbw/record.json
  [ ! -e .vbw/runtime/loop.s1 ]
  run stop s1
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

# T156: the loop's time counts only while it works. A turn of the loop's session that ends on an API
# error (StopFailure, the same hook script) leaves an away mark with the time it failed; the loop's
# session resumed (SessionStart, source resume) leaves an empty one (since the item's last step); an
# earlier mark is kept. The next loop step reads it (tests/loop-budget-stop.bats).
stop_failure() { jq -nc --arg s "$1" '{hook_event_name: "StopFailure", session_id: $s, error: "server_error"}' | vbw_hook StopFailure; }
session_start() { jq -nc --arg s "$1" --arg src "$2" '{hook_event_name: "SessionStart", session_id: $s, source: $src}' | vbw_hook SessionStart > /dev/null; }

@test "T156: a failed turn of the loop's session leaves the away mark with its time and says nothing; another session leaves none" {
  jq -e '(.hooks.StopFailure | length) == 1 and (.hooks.StopFailure[0].hooks[0].command | test("hooks/stop.sh"))' "$PLUGIN_ROOT/hooks/hooks.json"
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  run stop_failure s2
  [ "$status" -eq 0 ] && [ -z "$output" ] && [ ! -e .vbw/runtime/loop-away.s2 ] || { echo "$output"; false; }
  local sum
  sum=$(record_sum)
  run stop_failure s1
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; false; }
  [ "$(record_sum)" = "$sum" ]
  jq -nRe --rawfile t .vbw/runtime/loop-away.s1 '$t | rtrimstr("\n") | fromdateiso8601 | . <= now and . > now - 120'
  # A later failure keeps the earlier time.
  printf '2026-10-24T08:00:00Z\n' > .vbw/runtime/loop-away.s1
  stop_failure s1 > /dev/null
  [ "$(cat .vbw/runtime/loop-away.s1)" = 2026-10-24T08:00:00Z ]
}

@test "T156: the loop's session resumed leaves an empty away mark, keeping an earlier one; a compact or another session leaves none; the loop's end removes it" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  session_start s1 compact
  session_start s2 resume
  [ ! -e .vbw/runtime/loop-away.s1 ]
  [ ! -e .vbw/runtime/loop-away.s2 ]
  session_start s1 resume
  [ -f .vbw/runtime/loop-away.s1 ]
  [ ! -s .vbw/runtime/loop-away.s1 ]
  printf '2026-10-24T08:00:00Z\n' > .vbw/runtime/loop-away.s1
  session_start s1 resume
  [ "$(cat .vbw/runtime/loop-away.s1)" = 2026-10-24T08:00:00Z ]
  VBW_SESSION_ID=s1 "$VBW" loop stop > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop stop > /dev/null
  jq -e '.loop.ended != null' .vbw/record.json
  [ ! -e .vbw/runtime/loop-away.s1 ]
}

@test "T150: outside a VBW project and with no loop or armed run the hook says nothing" {
  run stop s1
  [ "$status" -eq 0 ] && [ -z "$output" ]
  mkdir "$TEST_ROOT/plain"
  HOOK_PROJECT_DIR="$TEST_ROOT/plain" run stop s1
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run bash -c 'printf "%s" "{\"session_id\": \"../x\"}" | CLAUDE_PROJECT_DIR="$1" bash "$2/hooks/stop.sh"' _ "$PROJECT" "$PLUGIN_ROOT"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}
