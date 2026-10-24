#!/usr/bin/env bash
# The clock inside a proof (R202, docs/proof.md): vbw prove and vbw fix done
# time the steps that are VBW's own work, not a unit's command running:
# planning (reading the record and the contract, what to reuse, the scope check
# and the trees of the committed code and of the working folder), copies (the
# clean copies), tracking (each unit's read reset before and read list
# collected after), saving (the run store and the kept output) and record
# (building the evidence and writing the plan of record). The other steps tile
# the command from the timer's start to the end of the record step: each
# prooftime_step counts the time since the last mark into its step, and a wait
# for a slot or the units' commands are passed uncounted (prooftime_mark). A
# unit runs in a subshell and counts its own tracking (prooftime_span), so
# tracking is summed over the units that run side by side. Each count is a line
# in a scratch file of this process under the runtime folder; the total sums
# them. Without a timer open (vbw check) every count is a no-op. Seconds carry
# milliseconds. JSON only through jq.

PROOFTIME_FILE=''
PROOFTIME_T0=''
PROOFTIME_AT=''
PROOFTIME_NS=''

# prooftime_detect: which clock this machine has (date's %N where it is
# honoured, else perl's Time::HiRes, else whole seconds); decided once, in the
# shell that opens the timer, so a unit's subshell inherits it.
prooftime_detect() {
  local n
  n=$(date +%N 2> /dev/null) || n=
  case "$n" in
    '' | *[!0-9]*) if perl -MTime::HiRes -e '1' > /dev/null 2>&1; then PROOFTIME_NS=perl; else PROOFTIME_NS=none; fi ;;
    *) PROOFTIME_NS=nanos ;;
  esac
}

# prooftime_clock: now, in seconds with milliseconds.
prooftime_clock() {
  local n
  [ -n "$PROOFTIME_NS" ] || prooftime_detect
  case "$PROOFTIME_NS" in
    nanos) n=$(date +%s.%N) && printf '%s.%s\n' "${n%.*}" "$(printf '%s' "${n#*.}" | cut -c1-3)" ;;
    perl) perl -MTime::HiRes=time -e 'printf "%.3f\n", time' ;;
    *) printf '%s.000\n' "$(date +%s)" ;;
  esac
}

# prooftime_ms CLOCK: a clock reading as whole milliseconds.
prooftime_ms() {
  local s="${1%.*}" f="${1#*.}"
  [ "$f" != "$1" ] || f=0
  f="${f}000"
  printf '%s\n' "$((10#${s:-0} * 1000 + 10#${f:0:3}))"
}

# prooftime_begin: open the timer (a scratch file of this process); the wall clock starts now.
prooftime_begin() {
  prooftime_detect
  PROOFTIME_T0=$(prooftime_clock)
  PROOFTIME_AT=$PROOFTIME_T0
  PROOFTIME_FILE=''
  if [ -n "${VBW_RUNTIME:-}" ] && mkdir -p "$VBW_RUNTIME" 2> /dev/null && : > "$VBW_RUNTIME/prooftime.$$" 2> /dev/null; then
    PROOFTIME_FILE=$VBW_RUNTIME/prooftime.$$
    vbw_guard_add file "$PROOFTIME_FILE"
  fi
}

# prooftime_add STEP SECONDS: count SECONDS (decimal) into STEP; nothing without a timer.
prooftime_add() {
  [ -n "$PROOFTIME_FILE" ] || return 0
  printf '%s %s\n' "$1" "$2" >> "$PROOFTIME_FILE" 2> /dev/null || true
}

# prooftime_span STEP START: count the time since START (a prooftime_clock reading) into STEP.
prooftime_span() {
  [ -n "$PROOFTIME_FILE" ] || return 0
  local d
  d=$(($(prooftime_ms "$(prooftime_clock)") - $(prooftime_ms "$2")))
  [ "$d" -ge 0 ] || d=0
  prooftime_add "$1" "$(printf '%d.%03d' "$((d / 1000))" "$((d % 1000))")"
}

# prooftime_step STEP: count the time since the last mark into STEP, and mark
# now: one clock reading ends this step and starts the next. Called directly,
# never in $(...) or a subshell.
prooftime_step() {
  [ -n "$PROOFTIME_FILE" ] || return 0
  local now d
  now=$(prooftime_clock)
  d=$(($(prooftime_ms "$now") - $(prooftime_ms "$PROOFTIME_AT")))
  [ "$d" -ge 0 ] || d=0
  prooftime_add "$1" "$(printf '%d.%03d' "$((d / 1000))" "$((d % 1000))")"
  PROOFTIME_AT=$now
}

# prooftime_mark: mark now, counting nothing: the time since the last mark was a
# wait for a slot or the units' commands. Called directly, never in $(...).
prooftime_mark() {
  [ -n "$PROOFTIME_FILE" ] || return 0
  PROOFTIME_AT=$(prooftime_clock)
}

# prooftime_total: {planning, copies, tracking, saving, record, wall} in
# seconds; wall is the time since the timer opened, read now (vbw prove and vbw
# fix done read it after their record step, so it covers every other step).
prooftime_total() {
  local wall=0
  if [ -n "$PROOFTIME_T0" ]; then
    wall=$(($(prooftime_ms "$(prooftime_clock)") - $(prooftime_ms "$PROOFTIME_T0")))
    [ "$wall" -ge 0 ] || wall=0
  fi
  {
    [ -z "$PROOFTIME_FILE" ] || cat "$PROOFTIME_FILE" 2> /dev/null
  } | jq -R -s -c --argjson wall "$wall" '
    [split("\n")[] | select(length > 0) | split(" ") | {k: .[0], v: (.[1] | tonumber)}] as $l
    | def sum($k): ([$l[] | select(.k == $k) | .v] | add // 0) | . * 1000 | round / 1000;
      {planning: sum("planning"), copies: sum("copies"), tracking: sum("tracking"), saving: sum("saving"), record: sum("record"),
       wall: ($wall / 1000)}'
}

# prooftime_end: close the timer.
prooftime_end() {
  [ -z "$PROOFTIME_FILE" ] || vbw_guard_drop "$PROOFTIME_FILE"
  PROOFTIME_FILE=''
}

# PROOFTIME_RANK_JQ: the one counting and ranking of "ran again", over an
# evidence-shaped object ({causes, checks, commands, test_files}): ranked is
# {ran, total, top: [{r, c}]}. Units are the checks that did not wait, the
# commands that were not skipped and are not of_files, and the test files; those
# without reused ran again. A unit's reason is its why, or each cause of the
# whole proof when it has none; at most three, most frequent first, ties in the
# units' order.
# shellcheck disable=SC2016 # a jq program
PROOFTIME_RANK_JQ='def ranked:
  ((.causes // []) ) as $c
  | ([(.checks // {}) | to_entries[] | select(.value.status != "waiting")]
     + [(.commands // {}) | to_entries[] | select(.value.status != "skipped" and (.value.of_files | not))]
     + [(.test_files // {}) | to_entries[]]) as $u
  | [$u[] | select(.value.reused | not)] as $ran
  | [$ran[] | if .value.why then [.value.why] else $c end | .[]] as $rs
  | {ran: ($ran | length), total: ($u | length),
     top: (reduce $rs[] as $r ([]; if any(.[]; .r == $r) then map(if .r == $r then .c += 1 else . end) else . + [{r: $r, c: 1}] end)
           | sort_by(-.c) | .[:3])};
'

# prooftime_lines: from an evidence-shaped object on stdin ({own, causes, checks,
# commands, test_files}) print the two report lines (the ranking is
# PROOFTIME_RANK_JQ's).
prooftime_lines() {
  jq -r "$PROOFTIME_RANK_JQ"'
    def min: (. / 6 | round) as $t | "\($t / 10 | floor).\($t % 10)";
    (.own // {}) as $o
    | ([($o.planning // 0), ($o.copies // 0), ($o.tracking // 0), ($o.saving // 0), ($o.record // 0)] | add) as $x
    | ranked as $k
    | "VBW'"'"'s own work: \($x | min) of \(($o.wall // 0) | min) min",
      "ran again: \($k.ran) of \($k.total) units; top reasons: "
        + (if $k.ran == 0 then "none" elif ($k.top | length) == 0 then "not recorded"
           else ($k.top | map("\(.r) (\(.c))") | join(", ")) end)'
}

# prooftime_top: from an evidence-shaped object on stdin, the reason most units
# run again as {reason, count}, or null when none runs or none is recorded.
prooftime_top() {
  jq -c "$PROOFTIME_RANK_JQ"'ranked.top[0] // null | if . == null then null else {reason: .r, count: .c} end'
}
