#!/usr/bin/env bash
# A proof as a step (R190, docs/panel.md): vbw prove, and the proof inside vbw
# fix done, count the units they run (a check, a test file, a project command)
# in the running step's note, .vbw/runtime/step.json, as each one finishes.
#
# Three cases, decided once when the proof starts (proofsteps_begin):
#   own    no live note and no run of this session open: the proof writes a note
#          of its own (kind proof, run null, its pid, parts {done, total}, an end
#          time from the proof history) and removes it when it ends;
#   inside a note of this session's open build, fix or other run is live: the
#          proof only sets doing ("proving 12 of 40 checks") and proof {done,
#          total}, and clears them when it ends; parts and end time stay;
#   none   a live note of anything else (another session's step, another
#          proof): never touched.
# Before it starts, a note that is not live (an ended run's, a dead process's)
# is removed. When it ends, the units that really finished are recorded as a step
# of kind proof (nothing when none ran). Units count only while PROOFSTEPS_ON=1,
# so vbw check never touches the note. All of it is best effort: a note or a
# history that cannot be written never fails a proof. JSON only through jq.

# shellcheck source=steps.sh
. "$VBW_LIB/steps.sh"

# proofsteps_lock: one writer of the note at a time (a mkdir lock; one whose
# owner process is gone, or that is over 5 s old, is taken over). Fails, and the
# caller skips its update, where the runtime folder is missing.
proofsteps_lock() {
  local l="$VBW_RUNTIME/step.lock" i=0 owner
  [ -d "$VBW_RUNTIME" ] || return 1
  while ! mkdir "$l" 2> /dev/null; do
    owner=$(cat "$l/pid" 2> /dev/null) || owner=
    if [ -n "$owner" ] && ! kill -0 "$owner" 2> /dev/null; then
      rm -rf "$l"
      continue
    fi
    i=$((i + 1))
    if [ "$i" -gt 500 ]; then
      rm -rf "$l"
      mkdir "$l" 2> /dev/null || return 1
      break
    fi
    sleep 0.01
  done
  printf '%s\n' "$$" > "$l/pid" 2> /dev/null || true
  return 0
}

proofsteps_unlock() {
  rm -rf "$VBW_RUNTIME/step.lock" 2> /dev/null || true
}

# proofsteps_commands RECORD NAMES: how many of the project commands in NAMES (a
# JSON array) a proof will run: those whose exact argv the user approved.
proofsteps_commands() {
  local name argv a n=0
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then n=$((n + 1)); fi
  done < <(printf '%s' "$1" | jq -j --argjson t "$2" '.commands | keys[] | select(. as $k | $t | index($k)) | . + "\u0000"')
  printf '%s\n' "$n"
}

# proofsteps_clean: remove a note that is not a running step (an ended run's, a
# dead process's); a proof does it before anything else, even when it runs nothing.
proofsteps_clean() {
  proofsteps_lock || return 0
  step_note_clean "$(record_read | jq -r '.lease.run // ""')"
  proofsteps_unlock
}

# proofsteps_begin TOTAL: a proof of TOTAL units starts. Sets PROOFSTEPS_ON,
# PS_MODE (own, inside or none) and what the later calls need.
proofsteps_begin() {
  local record lease run me live now expect first_end=null
  PROOFSTEPS_ON=1
  PS_TOTAL=$1
  PS_MODE=none
  PS_RUN=
  PS_DOING=
  PS_START=$(vbw_now)
  PS_COUNT="$VBW_RUNTIME/proofsteps.$$.count"
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || true
  printf '0\n' > "$PS_COUNT" 2> /dev/null || true
  vbw_guard_add file "$PS_COUNT"
  me=$(vbw_session)
  record=$(record_read)
  lease=$(printf '%s' "$record" | jq -c '.lease // empty')
  run=$(printf '%s' "$lease" | jq -r '.run // ""')
  proofsteps_lock || return 0
  step_note_clean "$run"
  live=$(step_live_note "$run")
  if [ -z "$live" ]; then
    if [ -z "$lease" ] || ! printf '%s' "$lease" | jq -e --arg me "$me" '(.session // "") == $me' > /dev/null; then
      PS_MODE=own
      expect=$(step_expect proof "$PS_TOTAL")
      now=$(vbw_now)
      [ -z "$expect" ] || first_end=$(jq -n -r --arg now "$now" --argjson e "$expect" '($now | fromdateiso8601) + $e | todateiso8601')
      vbw_guard_add file "$(step_note_file)"
      step_note_write "$(jq -n -c --arg me "$me" --argjson pid "$$" --arg now "$PS_START" --argjson t "$PS_TOTAL" --arg fe "$first_end" '
        {kind: "proof", run: null, session: (if $me == "" then null else $me end), pid: $pid, started_at: $now, ids: [],
         doing: "proving 0 of \($t) checks", parts: {done: 0, total: $t}, proof: null,
         first_end: (if $fe == "null" then null else $fe end), end: (if $fe == "null" then null else $fe end), late: false}')"
    fi
  elif printf '%s' "$live" | jq -e --arg me "$me" '.pid == null and (.session // "") == $me' > /dev/null; then
    PS_MODE=inside
    PS_RUN=$run
    PS_DOING=$(printf '%s' "$live" | jq -r '.doing')
    step_note_write "$(printf '%s' "$live" | jq -c --argjson t "$PS_TOTAL" '.proof = {done: 0, total: $t} | .doing = "proving 0 of \($t) checks"')"
  fi
  proofsteps_unlock
}

# proofsteps_note_update N: the note says N units done (the lock is held).
proofsteps_note_update() {
  local note out total=$PS_TOTAL
  [ "$PS_MODE" != none ] || return 0
  note=$(step_note_file)
  [ -f "$note" ] || return 0
  [ "$1" -le "$total" ] || total=$1
  out=$(jq -c --argjson d "$1" --argjson t "$total" --arg mode "$PS_MODE" --arg run "$PS_RUN" --argjson pid "$$" '
    if $mode == "own" then select(.kind == "proof" and .pid == $pid) | .parts = {done: $d, total: $t}
    else select(.pid == null and .run == $run and (.proof | type) == "object") | .proof = {done: $d, total: $t} end
    | .doing = "proving \($d) of \($t) checks"' "$note" 2> /dev/null) || return 0
  [ -z "$out" ] || step_note_write "$out"
}

# proofsteps_unit_done: a unit just finished (called from the unit's own
# process, in any lane). Counts it once, then rewrites the note.
proofsteps_unit_done() {
  local n
  [ "${PROOFSTEPS_ON:-}" = 1 ] || return 0
  proofsteps_lock || return 0
  n=$(cat "$PS_COUNT" 2> /dev/null) || n=0
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  printf '%s\n' "$n" > "$PS_COUNT" 2> /dev/null || true
  proofsteps_note_update "$n"
  proofsteps_unlock
}

# proofsteps_record N: the history gets a step of kind proof with N parts. The
# latest 50 of each kind are kept. Best effort, never fails the caller.
proofsteps_record() {
  local file now tmp
  file=$(step_history_file)
  [ -n "$file" ] || return 0
  [ ! -d "$file" ] || return 0
  now=$(vbw_now)
  tmp="$file.$$"
  mkdir -p "$(dirname "$file")" 2> /dev/null || return 0
  { jq -n -c --arg now "$now" --arg start "$PS_START" --argjson parts "$1" \
      --slurpfile old <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$file" 2> /dev/null) '
      ([$old[0].steps[]? | select(type == "object" and (.kind | type) == "string")]
        + [{kind: "proof", run: "proof-\($start | gsub("[-:]"; ""))", started_at: $start, ended_at: $now,
            seconds: (($now | fromdateiso8601) - ($start | fromdateiso8601)), parts: $parts}])
      | {steps: (group_by(.kind) | map(.[-50:]) | add | sort_by(.ended_at))}' > "$tmp" \
    && mv -f "$tmp" "$file"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  return 0
}

# proofsteps_end: the proof ended. Removes its own note, or gives the step its
# own wording back; records the units that really finished.
proofsteps_end() {
  local n note out
  [ "${PROOFSTEPS_ON:-}" = 1 ] || return 0
  n=$(cat "$PS_COUNT" 2> /dev/null) || n=0
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  if proofsteps_lock; then
    note=$(step_note_file)
    case "$PS_MODE" in
      own)
        if jq -e --argjson pid "$$" '.kind == "proof" and .pid == $pid' "$note" > /dev/null 2>&1; then
          vbw_guard_drop "$note"
        fi
        ;;
      inside)
        out=$(jq -c --arg run "$PS_RUN" --arg doing "$PS_DOING" 'select(.pid == null and .run == $run) | .proof = null | .doing = $doing' "$note" 2> /dev/null) || out=
        [ -z "$out" ] || step_note_write "$out"
        ;;
    esac
    proofsteps_unlock
  fi
  vbw_guard_drop "$PS_COUNT"
  PROOFSTEPS_ON=0
  [ "$n" -le 0 ] || proofsteps_record "$n"
  return 0
}

# proofsteps_fix_done N: vbw fix done closed N fixes: that many more parts done
# of the open fix step (this session's live note of kind fix).
proofsteps_fix_done() {
  local run note out
  [ "$1" -gt 0 ] || return 0
  run=$(record_read | jq -r '.lease.run // ""')
  [ -n "$(step_live_note "$run")" ] || return 0
  proofsteps_lock || return 0
  note=$(step_note_file)
  out=$(jq -c --argjson n "$1" --arg run "$run" 'select(.kind == "fix" and .pid == null and .run == $run and (.parts | type) == "object")
    | .parts.done = ([.parts.done + $n, .parts.total] | min)' "$note" 2> /dev/null) || out=
  [ -z "$out" ] || step_note_write "$out"
  proofsteps_unlock
}
