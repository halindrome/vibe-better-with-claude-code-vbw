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

@test "T150: outside a VBW project and with no loop or armed run the hook says nothing" {
  run stop s1
  [ "$status" -eq 0 ] && [ -z "$output" ]
  mkdir "$TEST_ROOT/plain"
  HOOK_PROJECT_DIR="$TEST_ROOT/plain" run stop s1
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run bash -c 'printf "%s" "{\"session_id\": \"../x\"}" | CLAUDE_PROJECT_DIR="$1" bash "$2/hooks/stop.sh"' _ "$PROJECT" "$PLUGIN_ROOT"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}
