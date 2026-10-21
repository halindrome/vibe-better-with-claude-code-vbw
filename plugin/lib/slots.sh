#!/usr/bin/env bash
# The computer-wide slot store (R181, docs/proof.md). Every unit of vbw prove,
# vbw fix done and vbw check (a check, a project command, a test file) takes one
# slot for as long as its command runs, so all VBW runs on a computer, in every
# project and session, never run more units than vbw_machine_limit together.
#
# The store is <vbw_claude_dir>/vbw/slots.json, one JSON document
# {held: [{run, id}], waiting: [{run, id, order}], next}: "run" is the vbw
# process ($$), "id" the unit, "order" its place in the wait. Every change is
# one step under the short lock directory slots.lock/ (its owner's pid in
# slots.lock/pid, taken over when that process is gone, and when the pid file
# is empty only after a wait), written atomically (a temporary file in the same
# folder, then mv). The file is removed when nothing holds or waits for a slot.
#
# Turns (D339): a unit registers as waiting; on each look it drops the entries
# of runs whose process is gone, and takes a slot only when fewer than the limit
# are held and it is the chosen waiter: the waiting run holding the fewest
# slots, between equals the one that has waited longest.
#
# A unit's command gets VBW_SLOT_STORE, the store it holds a slot in: a vbw run
# started inside it on the same store takes no slot (the unit's covers it, D340).
# When the store cannot be used the run goes on under check_jobs alone.

SLOTS_STATE=off
SLOTS_LOCKED=
SLOTS_MARK=
SLOTS_UNIT=
SLOTS_SUB=
SLOTS_RESULT=
SLOTS_WAITED=0
SLOTS_LOST=

# One step over a store already stripped of dead runs ($dead): the programs of
# slots_apply, each giving {store, result}.
SLOTS_ALIVE='def alive: select(.run as $r | ($dead | index($r)) == null); .held |= map(alive) | .waiting |= map(alive)'
SLOTS_TAKE="$SLOTS_ALIVE"'
  | if any(.held[]; .run == $run and .id == $id) then {store: ., result: true} else
      (if any(.waiting[]; .run == $run and .id == $id) then . else (.waiting += [{run: $run, id: $id, order: .next}] | .next += 1) end) as $s
      | $s.held as $h
      | ($s.waiting | min_by([(.run as $r | [$h[] | select(.run == $r)] | length), .order])) as $pick
      | if ($h | length) < $limit and $pick.run == $run and $pick.id == $id
        then {store: ($s | .waiting |= map(select((.run == $run and .id == $id) | not)) | .held += [{run: $run, id: $id}]), result: true}
        else {store: $s, result: false} end
    end'
SLOTS_DROP="$SLOTS_ALIVE"'
  | def mine: .run == $run and ($id == "" or .id == $id);
  .held |= map(select(mine | not)) | .waiting |= map(select(mine | not)) | {store: ., result: true}'

# slots_live PID: the process is alive (kill -0 is only a liveness probe).
slots_live() {
  [ -n "$1" ] && kill -0 "$1" 2> /dev/null
}

# slots_lock: take the store's lock; 2 when the folder cannot be written.
slots_lock() {
  local lock="$SLOTS_DIR/slots.lock" idle=0 owner
  while :; do
    # The owner file decides (vbw_lock_dir): a racing mkdir that also succeeded,
    # or a lock that vanished before its owner was written, waits and retries.
    if vbw_lock_dir "$lock"; then
      SLOTS_LOCKED=$lock
      return 0
    elif [ ! -d "$lock" ] && [ ! -w "$SLOTS_DIR" ]; then
      return 2
    fi
    # The owner is read once: empty means a handover in progress, never a dead owner.
    owner=$(cat "$lock/pid" 2> /dev/null)
    # A live owner is not an error: the wait for it has no end. Only a lock
    # that cannot be taken over (no live owner) gives up, after 600 tries.
    if [ -n "$owner" ] && slots_live "$owner"; then
      idle=0
    else
      idle=$((idle + 1))
      [ "$idle" -le 600 ] || return 2
    fi
    if [ -n "$owner" ]; then
      slots_live "$owner" || rm -rf "$lock" 2> /dev/null
    elif [ "$idle" -gt 50 ]; then
      rm -rf "$lock" 2> /dev/null
    fi
    sleep 0.05
  done
}

slots_unlock() {
  [ -z "$SLOTS_LOCKED" ] || rm -rf "$SLOTS_LOCKED" 2> /dev/null
  SLOTS_LOCKED=
}

# slots_read: print the store (a new one when there is none); 2 when it cannot
# be read, 3 when it is damaged (not JSON, or not the store's shape).
slots_read() {
  local json
  [ -e "$SLOTS_FILE" ] || { printf '{"held":[],"waiting":[],"next":1}\n'; return 0; }
  json=$(cat "$SLOTS_FILE" 2> /dev/null) || return 2
  printf '%s' "$json" | jq -e 'type == "object" and (.held | type) == "array" and (.waiting | type) == "array" and (.next | type) == "number"' > /dev/null 2>&1 || return 3
  printf '%s\n' "$json"
}

# slots_write JSON: the new store, atomically; none left when nothing holds or waits.
slots_write() {
  local tmp
  if printf '%s' "$1" | jq -e '(.held | length) + (.waiting | length) == 0' > /dev/null; then
    rm -f "$SLOTS_FILE" 2> /dev/null || return 2
    return 0
  fi
  tmp=$(mktemp "$SLOTS_DIR/slots.XXXXXX") || return 2
  { printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$SLOTS_FILE"; } 2> /dev/null || { rm -f "$tmp"; return 2; }
}

# slots_apply PROGRAM JQARG...: one locked step; the program's result is in SLOTS_RESULT.
slots_apply() {
  local prog="$1" json pids p dead='' out rc
  shift
  slots_lock || return 2
  json=$(slots_read) && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then slots_unlock; return "$rc"; fi
  pids=$(printf '%s' "$json" | jq -r '[.held[], .waiting[] | .run] | unique | .[]')
  for p in $pids; do slots_live "$p" || dead="$dead,$p"; done
  out=$(printf '%s' "$json" | jq -c --argjson dead "[${dead#,}]" "$@" "$prog") || { slots_unlock; return 3; }
  SLOTS_RESULT=$(printf '%s' "$out" | jq -c '.result')
  slots_write "$(printf '%s' "$out" | jq -c '.store')" && rc=0 || rc=$?
  slots_unlock
  return "$rc"
}

# slots_open: once per command (checks_begin). The store in force: SLOTS_STATE
# on; a run inside a unit on this same store: nested (no slots of its own); a
# store that cannot be used: off, said once on stderr.
slots_open() {
  local why rc
  SLOTS_STATE=off
  SLOTS_DIR="$(vbw_claude_dir)/vbw"
  SLOTS_FILE="$SLOTS_DIR/slots.json"
  SLOTS_LIMIT=$(vbw_machine_limit)
  if [ "${VBW_SLOT_STORE:-}" = "$SLOTS_FILE" ]; then SLOTS_STATE=nested; return 0; fi
  why="cannot write $SLOTS_FILE"
  if mkdir -p "$SLOTS_DIR" 2> /dev/null && slots_lock; then
    slots_read > /dev/null && rc=0 || rc=$?
    slots_unlock
    case "$rc" in
      0)
        SLOTS_STATE=on
        [ "$VBW_GUARD_EXIT" -eq 0 ] || trap 'slots_gone ""; vbw_guard_run' EXIT
        return 0
        ;;
      3) why="$SLOTS_FILE is damaged (delete it to restore the limit)" ;;
    esac
  fi
  printf "vbw: the computer-wide limit was not in force: %s; this run was limited by check_jobs (%s) alone\n" "$why" "$(vbw_check_jobs || printf 1)" >&2
}

# slots_traps: on Ctrl-C, TERM and HUP this run's entries (the unit's own in a
# runner) are removed before the guard's cleanup. The EXIT trap (vbw_die ends
# through it) is set once, by slots_open, never in a subshell.
slots_traps() {
  trap 'slots_gone "$SLOTS_UNIT"; vbw_guard_run; exit 130' INT
  trap 'slots_gone "$SLOTS_UNIT"; vbw_guard_run; exit 143' TERM
  trap 'slots_gone "$SLOTS_UNIT"; vbw_guard_run; exit 129' HUP
}

# slots_gone [UNIT]: remove this run's entries (or the unit's), best effort.
slots_gone() {
  [ "$SLOTS_STATE" = on ] || return 0
  slots_unlock
  slots_apply "$SLOTS_DROP" --argjson run "$$" --arg id "${1:-}" > /dev/null 2>&1 || true
}

# slots_lose RC: the store failed in the middle of the run (RC of slots_apply):
# this process goes on without slots, and the run's marker file tells the parent
# (a runner is a subshell whose stderr is hidden), which says it once at the end.
slots_lose() {
  local why="cannot write $SLOTS_FILE"
  SLOTS_STATE=off
  SLOTS_MARK=
  [ "$1" -ne 3 ] || why="$SLOTS_FILE is damaged (delete it to restore the limit)"
  { [ -f "$CHECK_OUT/lost" ] || printf '%s\n' "$why" > "$CHECK_OUT/lost"; } 2> /dev/null || true
}

# slots_hold NAME: wait for a slot of the store and hold it under NAME, without
# the unit mark (a bookkeeping step of the run, R202: vbw:plan, vbw:copies,
# vbw:save). 1 when no slot is in force (store off, lost on the way, or a nested
# run, which takes none): the step then runs anyway.
slots_hold() {
  [ "$SLOTS_STATE" = on ] || return 1
  slots_traps
  local since="" rc
  while :; do
    slots_apply "$SLOTS_TAKE" --argjson run "$$" --arg id "$1" --argjson limit "$SLOTS_LIMIT" && rc=0 || rc=$?
    if [ "$rc" -ne 0 ]; then slots_lose "$rc"; return 1; fi
    [ "$SLOTS_RESULT" != true ] || break
    [ -n "$since" ] || since=$(date +%s)
    sleep 0.1
  done
  slots_waited "$since"
}

# slots_release NAME: give a bookkeeping slot back.
slots_release() {
  local rc
  [ "$SLOTS_STATE" = on ] || return 0
  slots_apply "$SLOTS_DROP" --argjson run "$$" --arg id "$1" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || slots_lose "$rc"
  return 0
}

# slots_take UNIT: wait for a slot of the store, then hold it (the mark names the store for the unit's command).
slots_take() {
  [ "$SLOTS_STATE" = on ] || return 0
  [ -z "$SLOTS_SUB" ] || SLOTS_UNIT=$1
  slots_hold "$1" || return 0
  SLOTS_MARK="VBW_SLOT_STORE=$SLOTS_FILE"
}

# slots_waited SINCE: note how long a unit waited for its slot (SINCE: the
# second it first found none, empty when it found one at once): whole seconds,
# at least 1, one line in the run's waits file. The wait is told to the user
# only (slots_say): it never reaches evidence, the record or the stored runs.
slots_waited() {
  local n
  [ -n "$1" ] || return 0
  n=$(($(date +%s) - $1))
  [ "$n" -ge 1 ] || n=1
  printf '%s\n' "$n" >> "$CHECK_OUT/waits" 2> /dev/null || true
}

# slots_total: the seconds all units of this command waited, taken before
# checks_end removes the run's folder (SLOTS_WAITED).
slots_total() {
  SLOTS_WAITED=0 SLOTS_LOST=
  [ ! -f "$CHECK_OUT/lost" ] || SLOTS_LOST=$(head -n 1 "$CHECK_OUT/lost")
  [ ! -f "$CHECK_OUT/waits" ] || SLOTS_WAITED=$(awk '{ n += $1 } END { print n + 0 }' "$CHECK_OUT/waits")
}

# slots_say: the last line of a command whose units waited, nothing otherwise.
slots_say() {
  local cores t
  if [ -n "$SLOTS_LOST" ]; then
    printf "vbw: the computer-wide limit was not in force: %s; this run was limited by check_jobs (%s) alone from then on\n" "$SLOTS_LOST" "$(vbw_check_jobs || printf 1)" >&2
  fi
  [ "${SLOTS_WAITED:-0}" -gt 0 ] || return 0
  if [ "$SLOTS_WAITED" -ge 60 ]; then t="$((SLOTS_WAITED / 60)) min"; else t="$SLOTS_WAITED s"; fi
  if cores=$(vbw_cores); then
    printf "waited %s for other VBW runs on this computer (limit %s of %s cores)\n" "$t" "$SLOTS_LIMIT" "$cores"
  else
    printf "waited %s for other VBW runs on this computer (limit %s, as this computer's core count could not be read)\n" "$t" "$SLOTS_LIMIT"
  fi
}

# slots_give UNIT: give the slot back (also the place of a unit still waiting).
slots_give() {
  local rc
  # shellcheck disable=SC2034 # read by checks_exec
  SLOTS_MARK=
  [ "$SLOTS_STATE" = on ] || return 0
  slots_apply "$SLOTS_DROP" --argjson run "$$" --arg id "$1" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || slots_lose "$rc"
  return 0
}
