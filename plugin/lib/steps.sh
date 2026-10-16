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

# The kernel's one wording of a step, for vbw status, vbw next and vbw run start
# (the panel's words, D425). $t is the moment, in epoch seconds.
# step_clock($iso; $t): the local 24-hour time of a UTC time; "tomorrow HH:MM",
# "yesterday HH:MM" or the weekday when it is not today.
# step_words($s; $t): a note's time: 'about 12 min, until around 14:20',
# 'less than a minute, ...', 'until around 14:35, later than usual' (with parts),
# 'until around 14:20, 6 min late' (without), or 'no end time yet (...)'.
# step_label($kind; $ids; $n): what a step is: 'Building P1.1, P1.2 and P1.3'.
# step_say($s; $t): the sentence VBW says before a step starts; $s has kind,
# ids, parts (a number or {done, total}), end, late.
# step_sentence($s; $t): what a running step is doing, its progress and its time.
# shellcheck disable=SC2016,SC2034
VBW_STEP_DEFS='def step_day($e): $e | localtime | mktime / 86400 | floor;
def step_clock($iso; $t):
  ($iso | fromdateiso8601) as $e
  | ($e | localtime | strftime("%H:%M")) as $hm
  | (step_day($e) - step_day($t)) as $d
  | if $d == 0 then $hm
    elif $d == 1 then "tomorrow \($hm)"
    elif $d == -1 then "yesterday \($hm)"
    else "\($e | localtime | strftime("%A")) \($hm)" end;
def step_words($s; $t):
  if $s.end == null then "no end time yet (VBW has timed fewer than 3 steps like this here)"
  else (($s.end | fromdateiso8601) - $t) as $left
    | "until around \(step_clock($s.end; $t))" as $at
    | (($s.parts // null) != null) as $hp
    | if $hp and ($s.late == true or $left <= 0) then "\($at), later than usual"
      elif ($hp | not) and $left <= -60 then "\($at), \(-$left / 60 | floor) min late"
      elif $left < 60 then (if $left > 0 then "less than a minute, \($at)" else $at end)
      else "about \([1, ($left / 60 | round)] | max) min, \($at)" end end;
def step_and: if length < 2 then join("") else (.[:-1] | join(", ")) + " and " + .[-1] end;
def step_label($k; $ids; $n):
  if $k == "build" then "Building \($ids | step_and)"
  elif $k == "fix" then "Fixing \($ids | step_and)"
  elif $k == "qa" then (if ($ids | length) > 0 then "Checking \($ids | step_and)" else "Checking the built work" end)
  elif $k == "plan" then "Planning the work"
  elif $k == "proof" then "Proving \($n) \(if $n == 1 then "check" else "checks" end)"
  else "Mapping the project" end;
def step_say($s; $t):
  step_label($s.kind; $s.ids // []; if ($s.parts | type) == "object" then $s.parts.total else ($s.parts // 0) end)
  + ": " + step_words($s; $t);
def step_sentence($s; $t):
  $s.doing
  + (if ($s.parts // null) != null and ($s.proof // null) == null and $s.kind != "proof" then " · \($s.parts.done) of \($s.parts.total)" else "" end)
  + " · " + step_words($s; $t);
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

# step_say_note: the sentence of the note just written (run start), nothing
# without a note.
step_say_note() {
  local note
  note=$(step_note_file)
  [ -f "$note" ] || return 0
  jq -r "$VBW_STEP_DEFS"'step_say(.; now | floor)' "$note" 2> /dev/null || true
}

# step_proof_units RECORD FULL: how many units a proof would run now, planned
# by the proof's own reuse rule (cmd-prove.sh) without running anything.
step_proof_units() {
  (
    cd "$VBW_ROOT" || exit 1
    # shellcheck source=cmd-prove.sh
    . "$VBW_LIB/cmd-prove.sh"
    local causes alln=0
    proofreuse_plan "$1" "$2"
    causes=$(proofcauses_find "$1" "$2" "$(vbw_head_tree 2> /dev/null)")
    [ -z "$causes" ] || alln=1
    testfiles_plan "$1" "$alln"
    [ -z "$causes" ] || prove_plan_all "$1"
    printf '%s\n' "$(( ${#TODO_CHECKS[@]} + $(printf '%s' "$TODO_COMMANDS" | jq 'length') + ${#TF_TODO[@]} ))"
  ) 2> /dev/null || echo 0
}

# step_next RECORD NEXT: the step vbw next --json carries: {kind, ids, parts,
# seconds, end, say} for an answer that runs a step (plan, build, fix, qa, a
# proof with units left to run), else null. A kind without parts has parts null.
step_next() {
  local kind ids='[]' parts=null full units seconds=
  case "$(printf '%s' "$2" | jq -r .action)" in
    plan) kind=plan ;;
    build) kind=build ids=$(printf '%s' "$2" | jq -c .detail.plans) ;;
    fix) kind=fix ids=$(printf '%s' "$2" | jq -c .detail.fixes) ;;
    qa) kind=qa ids=$(printf '%s' "$2" | jq -c .detail.phases) ;;
    prove)
      kind=proof
      full=0
      printf '%s' "$2" | jq -e '.detail.full == true' > /dev/null && full=1
      units=$(step_proof_units "$1" "$full")
      [ "${units:-0}" -gt 0 ] 2> /dev/null || { echo null; return 0; }
      parts=$units ;;
    *) echo null; return 0 ;;
  esac
  step_kind_has_parts "$kind" && [ "$parts" = null ] && parts=$(printf '%s' "$ids" | jq 'length')
  seconds=$(step_expect "$kind" "$(printf '%s' "$parts" | sed 's/^null$/0/')")
  jq -nc --arg k "$kind" --argjson ids "$ids" --argjson parts "$parts" --arg s "$seconds" "$VBW_STEP_DEFS"'
    (now | floor) as $t
    | (if $s == "" then null else ($s | tonumber) end) as $sec
    | {kind: $k, ids: $ids, parts: $parts, seconds: $sec, end: (if $sec == null then null else $t + $sec | todateiso8601 end)}
    | . + {say: step_say(.; $t)}'
}
