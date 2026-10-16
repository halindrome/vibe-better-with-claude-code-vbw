#!/usr/bin/env bash
# The step history and the running step's note (R190, docs/panel.md).
#
# History: $(git-common-dir)/vbw/steps.json, {"steps": [{kind, run, started_at,
# ended_at, seconds, parts?}]}, the latest 50 of each kind in time order. It is
# a cache of what this project's steps took: a missing, damaged or unwritable
# file never fails a step; it only means no end time yet.
#
# Note: .vbw/runtime/step.json, written only by the kernel, atomically, while a
# step runs: {kind, run, session, pid, started_at, ids, doing, parts, proof,
# first_end, end, late}. A time is UTC ISO 8601 to the second; first_end and end
# are null when there is no basis (fewer than 3 finished steps of the kind).
# JSON is read and written only through jq.

# The kernel's one wording of a step, for vbw status, vbw next and vbw run start:
# step_clock($iso): the local 24-hour time of a UTC time, "tomorrow HH:MM" (or
# the date) when it is not today; step_sentence($step): what the step is doing,
# its progress and its end time.
# shellcheck disable=SC2016,SC2034
VBW_STEP_DEFS='def step_clock($iso):
  ($iso | fromdateiso8601) as $t
  | ($t | localtime | strftime("%H:%M")) as $hm
  | (now | localtime | strftime("%Y-%m-%d")) as $today
  | ($t | localtime | strftime("%Y-%m-%d")) as $day
  | if $day == $today then $hm
    elif $day == ((now + 86400) | localtime | strftime("%Y-%m-%d")) then "tomorrow \($hm)"
    else "\($day) \($hm)" end;
def step_sentence($s):
  $s.doing
  + (if ($s.parts // null) != null and ($s.proof // null) == null then " · \($s.parts.done) of \($s.parts.total)" else "" end)
  + (if $s.end == null then " · no end time yet (VBW has timed fewer than 3 steps like this here)"
     else " · until \(step_clock($s.end))"
       + (if $s.late == true then ", later than usual"
          elif ($s.minutes_late // null) != null then ", \($s.minutes_late) min late" else "" end) end);
'

# step_history_file: the history's path, empty outside a git repository.
step_history_file() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || return 0
  printf '%s/vbw/steps.json\n' "$common"
}

step_note_file() {
  printf '%s/step.json\n' "$VBW_RUNTIME"
}

# step_kind_has_parts KIND: builds, fixes and proofs count their parts.
step_kind_has_parts() {
  case "$1" in build | fix | proof) return 0 ;; esac
  return 1
}

# step_expect KIND PARTS: the expected seconds of a step of KIND with PARTS
# parts (ignored for a kind without parts), empty when the history gives no
# basis: a kind with parts takes the median time per part over its latest 10
# finished steps that recorded parts, times PARTS; a kind without parts the
# median of its latest 10; an even count takes the mean of the two middle
# values; fewer than 3 such steps give nothing.
step_expect() {
  local file out
  file=$(step_history_file)
  [ -n "$file" ] && [ -f "$file" ] || return 0
  out=$(jq -r --arg k "$1" --argjson parts "${2:-0}" --argjson wp "$(step_kind_has_parts "$1" && echo true || echo false)" '
    def median: sort | length as $n
      | if $n % 2 == 1 then .[($n - 1) / 2 | floor] else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
    select(type == "object" and (.steps | type) == "array")
    | [.steps[] | select(type == "object" and .kind == $k and (.seconds | type) == "number" and .seconds >= 0)]
    | if $wp then
        map(select((.parts | type) == "number" and .parts > 0)) | .[-10:]
        | if length < 3 then empty else (map(.seconds / .parts) | median) * $parts | round end
      else .[-10:] | if length < 3 then empty else (map(.seconds) | median) | round end end' "$file" 2> /dev/null) || return 0
  printf '%s\n' "$out"
}

# step_record LEASE_JSON: add the run that just ended to the history, with its
# parts from its note. Best effort, never fails the caller.
step_record() {
  local file now tmp note parts=null
  file=$(step_history_file)
  [ -n "$file" ] || return 0
  [ ! -d "$file" ] || return 0
  now=$(vbw_now)
  tmp="$file.$$"
  note=$(step_note_file)
  if [ -f "$note" ]; then
    parts=$(jq -c --arg run "$(printf '%s' "$1" | jq -r '.run')" 'if .run == $run and (.parts | type) == "object" then .parts.total else null end' "$note" 2> /dev/null) || parts=null
    [ -n "$parts" ] || parts=null
  fi
  mkdir -p "$(dirname "$file")" 2> /dev/null || return 0
  { jq -c --arg now "$now" --argjson parts "$parts" --slurpfile old <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$file" 2> /dev/null) '
      ([$old[0].steps[]? | select(type == "object" and (.kind | type) == "string")]
        + [{kind, run, started_at, ended_at: $now,
            seconds: (($now | fromdateiso8601) - (.started_at | fromdateiso8601))}
           + (if $parts == null then {} else {parts: $parts} end)])
      | {steps: (group_by(.kind) | map(.[-50:]) | add | sort_by(.ended_at))}' <<< "$1" > "$tmp" \
    && mv -f "$tmp" "$file"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  return 0
}

# step_live_note RUN: print the note when it is a running step, else print
# nothing. A note with a process (a proof of its own) is live while the process
# is; any other is live while its run is the open run (RUN, empty: none).
step_live_note() {
  local note pid
  note=$(step_note_file)
  [ -f "$note" ] || return 0
  jq -e 'type == "object" and (.kind | type) == "string"' "$note" > /dev/null 2>&1 || return 0
  pid=$(jq -r '.pid // empty' "$note" 2> /dev/null) || return 0
  if [ -n "$pid" ]; then
    kill -0 "$pid" 2> /dev/null || return 0
    jq -c . "$note" 2> /dev/null || true
    return 0
  fi
  jq -c --arg run "$1" 'select($run != "" and .run == $run)' "$note" 2> /dev/null || true
}

# step_note_clean RUN: remove a note that is not a running step.
step_note_clean() {
  [ -f "$(step_note_file)" ] || return 0
  [ -n "$(step_live_note "$1")" ] || rm -f "$(step_note_file)" 2> /dev/null || true
  return 0
}

# step_note_write JSON: replace the note atomically; never fails the caller.
step_note_write() {
  local note tmp
  note=$(step_note_file)
  tmp="$note.$$"
  { mkdir -p "$VBW_RUNTIME" && printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$note"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  return 0
}

# step_qa_phases RECORD: the phases vbw next would send to QA: built phases of
# the milestone whose QA is due (lib/qa.jq's recheck, lib/rigor-defs.jq's
# needs_qa), the same rule as next.jq's $to_verify.
step_qa_phases() {
  local qa
  qa=$(qa_state "$1" 2> /dev/null) || { echo '[]'; return 0; }
  printf '%s' "$1" | jq -c --slurpfile qa <(printf '%s' "$qa") "$VBW_JQ_DEFS"'.milestone.id as $m
    | [.requirements[] | select(.milestone == $m)] as $current
    | [.phases[] | select(.milestone == $m and $qa[0].recheck[.id] != null and needs_qa(.tier // "standard"; $current)) | .id]' 2> /dev/null || echo '[]'
}

# step_start KIND IDS_JSON: write the note of the run that just started (the
# open run of the record), after removing a note that is not live.
step_start() {
  local kind="$1" ids="$2" record lease parts=null doing expect first_end=null
  record=$(record_read)
  lease=$(printf '%s' "$record" | jq -c '.lease // empty')
  [ -n "$lease" ] || return 0
  step_note_clean "$(printf '%s' "$lease" | jq -r '.run')"
  if [ "$kind" = qa ]; then
    # shellcheck source=cmd-next.sh
    . "$VBW_LIB/cmd-next.sh"
    ids=$(step_qa_phases "$record")
  fi
  if step_kind_has_parts "$kind"; then
    parts=$(printf '%s' "$ids" | jq -c '{done: 0, total: length}')
  fi
  doing=$(printf '%s' "$ids" | jq -r --arg k "$kind" '
    if $k == "build" then "building \(join(", "))"
    elif $k == "fix" then "fixing \(join(", "))"
    elif $k == "qa" then (if length > 0 then "checking \(join(", "))" else "checking the built work" end)
    elif $k == "plan" then "planning"
    else "mapping the project" end')
  expect=$(step_expect "$kind" "$(printf '%s' "$parts" | jq -r '.total // 0')")
  [ -z "$expect" ] || first_end=$(printf '%s' "$lease" | jq -r --argjson e "$expect" '(.started_at | fromdateiso8601) + $e | todateiso8601')
  step_note_write "$(printf '%s' "$lease" | jq -c --arg k "$kind" --argjson ids "$ids" --argjson parts "$parts" --arg doing "$doing" --arg fe "$first_end" '
    {kind: $k, run, session: (.session // null), pid: null, started_at, ids: $ids, doing: $doing, parts: $parts, proof: null,
     first_end: (if $fe == "null" then null else $fe end), end: (if $fe == "null" then null else $fe end), late: false}')"
}

# step_plan_done: a plan was just recorded done; count the running build's
# parts done from the record, and when this run's own pace ends after the first
# end time, move the end to that projection and mark it late (D424). The end
# never goes earlier than the first end time.
step_plan_done() {
  local run note out
  run=$(record_read | jq -r '.lease.run // ""')
  [ -n "$(step_live_note "$run")" ] || return 0
  note=$(step_note_file)
  out=$(jq -c --slurpfile r "$VBW_RECORD" '
    . as $n | ($r[0].plans) as $pl
    | select($n.kind == "build" and ($n.parts | type) == "object")
    | ([$n.ids[] | select(. as $i | any($pl[]; .id == $i and .status == "done"))] | length) as $done
    | .parts.done = $done
    | if .first_end == null or $done == 0 then .
      else (now | floor) as $t | ($t - (.started_at | fromdateiso8601)) as $el
        | ($t + ($el / $done * (.parts.total - $done) | round)) as $proj
        | (.first_end | fromdateiso8601) as $fe
        | (if $proj > $fe then $proj else $fe end) as $end
        | .end = ($end | todateiso8601) | .late = ($end > $fe) end' "$note" 2> /dev/null) || return 0
  [ -z "$out" ] || step_note_write "$out"
}

# step_status RUN: the running step as vbw status --json gives it: the live
# note, plus minutes_late (whole minutes past first_end for a step without
# parts, else null), or null.
step_status() {
  local live
  live=$(step_live_note "$1")
  if [ -z "$live" ]; then echo null; return 0; fi
  printf '%s' "$live" | jq -c '. + {minutes_late: (if .parts == null and .first_end != null
      then (((now | floor) - (.first_end | fromdateiso8601)) / 60 | floor | if . >= 1 then . else null end) else null end)}' 2> /dev/null || echo null
}
