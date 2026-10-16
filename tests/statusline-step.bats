#!/usr/bin/env bats
# R190, phase P147 (L1): while a step runs, the status line's first line shows
# the step, what it is doing and the clock time only (D425), read from the
# kernel's note (.vbw/runtime/step.json), never worked out by the status line:
# '▶ build P1.1, P1.2 · 1 of 2 · until 14:20'; a background proof 'proving 12 of
# 40 checks · until 14:26'; later than usual 'until 14:35, later than usual'; a
# late step without parts 'until 14:20, 6 min late'; no basis: the step and what
# it is doing, no time. Clock times are the computer's local time, 24-hour
# HH:MM; an end on another day names the day ('until tomorrow 00:20'). A note
# whose run is not the open run, or whose proof process is gone, shows nothing.
# The times here are local to Asia/Kolkata (UTC+05:30), so a UTC clock shows.

load helper
load step-helper

setup() {
  vbw_setup
  step_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  export TZ=Asia/Kolkata
  sleep 30 &
  LIVE=$!
}

teardown() {
  kill "$LIVE" 2> /dev/null || true
  wait 2> /dev/null || true
  vbw_teardown
}

render() {
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"}, version: "2.1.286"}' \
    | NO_COLOR=1 bash "$SL"
}

# hm FIELD: the local HH:MM of the note's FIELD (end or first_end).
hm() { jq -r --arg f "$1" '.[$f] | fromdateiso8601 | strflocaltime("%H:%M")' "$NOTE"; }

# note FILTER: write the note: the open run's, a build of P1.1 and P1.2 started
# 5 min ago, ending in 12 min, then FILTER (times as seconds from now: s(N)).
note() {
  jq -n --slurpfile r .vbw/record.json "def s(\$n): (now | floor) + \$n | todateiso8601;
    {kind: \"build\", run: \$r[0].lease.run, session: \"s1\", pid: null, started_at: s(-300), ids: [\"P1.1\", \"P1.2\"],
     doing: \"building P1.1, P1.2\", parts: {done: 1, total: 2}, proof: null, first_end: s(720), end: s(720), late: false} | $1" > "$NOTE"
}

@test "R190: a build shows the step, its plans, parts done and the clock time only" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note .
  run render
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"▶ build P1.1, P1.2 · 1 of 2 · until $(hm end)"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" != *"about"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a background proof shows 'proving N of M checks' and its clock time, and counts up" {
  jq -n --argjson pid "$LIVE" 'def s($n): (now | floor) + $n | todateiso8601;
    {kind: "proof", run: null, session: "s1", pid: $pid, started_at: s(-60), ids: [], doing: "proving 12 of 40 checks",
     parts: {done: 12, total: 40}, proof: {done: 12, total: 40}, first_end: s(480), end: s(480), late: false}' > "$NOTE"
  run render
  [[ "${lines[0]}" == *"proving 12 of 40 checks · until $(hm end)"* ]] || { echo "${lines[0]}"; false; }
  jq '.parts.done = 13 | .proof.done = 13 | .doing = "proving 13 of 40 checks"' "$NOTE" > "$TEST_ROOT/n.json" && cp "$TEST_ROOT/n.json" "$NOTE"
  run render
  [[ "${lines[0]}" == *"proving 13 of 40 checks · until $(hm end)"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a proof inside a fix shows as what the fix is doing; the time stays the fix's" {
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fix"
  "$VBW" run start fix F1 > /dev/null
  note '.kind = "fix" | .ids = ["F1"] | .parts = {done: 0, total: 1} | .proof = {done: 12, total: 40} | .doing = "proving 12 of 40 checks"'
  run render
  [[ "${lines[0]}" == *"▶ fix"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" == *"proving 12 of 40 checks"*"until $(hm end)"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a late step with parts shows its moved clock time, later than usual" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note '.first_end = s(-120) | .end = s(900) | .late = true'
  run render
  [[ "${lines[0]}" == *"until $(hm end), later than usual"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a late step without parts keeps its clock time and says how many minutes late" {
  "$VBW" run start plan > /dev/null
  note '.kind = "plan" | .ids = [] | .doing = "planning" | .parts = null | .first_end = s(-380) | .end = s(-380)'
  run render
  [[ "${lines[0]}" == *"until $(hm first_end), 6 min late"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: with no basis the step and what it is doing show, with no time" {
  step_edit '.phases[0].tier = "standard" | .plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" run start qa > /dev/null
  note '.kind = "qa" | .ids = ["P1"] | .doing = "checking P1" | .parts = null | .first_end = null | .end = null'
  run render
  [[ "${lines[0]}" == *"▶ qa"*"P1"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" != *"until"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: an end on another day names the day, in 24-hour local time" {
  export TZ=UTC
  "$VBW" run start build P1.1 P1.2 > /dev/null
  # 00:20 tomorrow, UTC.
  jq -n --slurpfile r .vbw/record.json '(now | floor) as $t | ($t - ($t % 86400) + 86400 + 1200) as $e
    | {kind: "build", run: $r[0].lease.run, session: "s1", pid: null, started_at: ($t - 300 | todateiso8601), ids: ["P1.1", "P1.2"],
       doing: "building P1.1, P1.2", parts: {done: 1, total: 2}, proof: null, first_end: ($e | todateiso8601), end: ($e | todateiso8601), late: false}' > "$NOTE"
  run render
  [[ "${lines[0]}" == *"until tomorrow 00:20"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a note whose run is not the open run, or whose proof process is gone, shows no step" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  # The open run's own note shows; the same note of another run does not.
  note .
  run render
  [[ "${lines[0]}" == *"1 of 2 · until"* ]] || { echo "${lines[0]}"; false; }
  note '.run = "build-20200101T000000Z"'
  run render
  [[ "${lines[0]}" != *"until"* && "${lines[0]}" != *"1 of 2"* ]] || { echo "${lines[0]}"; false; }
  "$VBW" run end > /dev/null
  note .
  run render
  [[ "${lines[0]}" != *"▶"* ]] || { echo "${lines[0]}"; false; }
  local gone
  sh -c 'exit 0' &
  gone=$!
  wait "$gone" || true
  jq -n --argjson pid "$gone" 'def s($n): (now | floor) + $n | todateiso8601;
    {kind: "proof", run: null, session: "s1", pid: $pid, started_at: s(-60), ids: [], doing: "proving 12 of 40 checks",
     parts: {done: 12, total: 40}, proof: {done: 12, total: 40}, first_end: s(480), end: s(480), late: false}' > "$NOTE"
  run render
  [[ "${lines[0]}" != *"proving"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: the status line works no time out itself: with the run open and no note, no end time" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note .
  run render
  [[ "${lines[0]}" == *"until"* ]] || { echo "${lines[0]}"; false; }
  rm -f "$NOTE"
  run render
  [[ "${lines[0]}" != *"until"* ]] || { echo "${lines[0]}"; false; }
}
