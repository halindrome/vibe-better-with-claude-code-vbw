#!/usr/bin/env bash
# The clock inside a proof (R202, docs/proof.md): vbw prove and vbw fix done
# time the steps that are VBW's own work, not a unit's command running:
# planning (what to reuse), copies (the clean copies), tracking (each unit's
# read reset before and read list collected after), saving (the run store) and
# record (writing the plan of record). A unit runs in a subshell, so each step
# adds its seconds as a line to a scratch file of this process under the
# runtime folder; the total sums them. Without a timer open (vbw check) every
# add is a no-op. Seconds carry milliseconds. JSON only through jq.

PROOFTIME_FILE=''
PROOFTIME_T0=''
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

# prooftime_total: {planning, copies, tracking, saving, record, wall} in seconds.
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

# prooftime_lines: from an evidence-shaped object on stdin ({own, causes, checks,
# commands, test_files}) print the two report lines. Units are the checks that
# did not wait, the commands that were not skipped and are not of_files, and
# the test files; those without reused ran again. A unit's reason is its why, or
# each cause of the whole proof when it has none; at most three, most frequent
# first, ties in the units' order.
prooftime_lines() {
  jq -r '
    def min: (. / 6 | round) as $t | "\($t / 10 | floor).\($t % 10)";
    (.own // {}) as $o
    | ([($o.planning // 0), ($o.copies // 0), ($o.tracking // 0), ($o.saving // 0), ($o.record // 0)] | add) as $x
    | ((.causes // []) ) as $c
    | ([(.checks // {}) | to_entries[] | select(.value.status != "waiting")]
       + [(.commands // {}) | to_entries[] | select(.value.status != "skipped" and (.value.of_files | not))]
       + [(.test_files // {}) | to_entries[]]) as $u
    | [$u[] | select(.value.reused | not)] as $ran
    | [$ran[] | if .value.why then [.value.why] else $c end | .[]] as $rs
    | (reduce $rs[] as $r ([]; if any(.[]; .r == $r) then map(if .r == $r then .c += 1 else . end) else . + [{r: $r, c: 1}] end)
       | sort_by(-.c) | .[:3]) as $top
    | "VBW'"'"'s own work: \($x | min) of \(($o.wall // 0) | min) min",
      "ran again: \($ran | length) of \($u | length) units; top reasons: "
        + (if ($ran | length) == 0 then "none" elif ($top | length) == 0 then "not recorded"
           else ($top | map("\(.r) (\(.c))") | join(", ")) end)'
}
