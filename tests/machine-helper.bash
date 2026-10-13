#!/usr/bin/env bash
# Shared by the R181 tests (docs/proof.md): one computer-wide limit on running
# checks, shared by every VBW project, session and run on the computer.
#
# The processor core count is faked: getconf, nproc and sysctl stand-ins first
# on PATH report the count in $TEST_ROOT/cores ("none": they fail), so the
# machine limit is three quarters of it. Every unit command is tests/unit.sh:
# it appends "start TIME NAME" before and "end TIME NAME" after its work to
# $LOG, a file the test owns. Each append is one small write, so the log's
# line order is the order the events happened, and the number of units running
# at the same moment is counted from it. The slot store exists only while a
# run holds or waits for a slot, so a test sees it from inside a run: a peek
# unit (tests/peek.sh PATH) copies the store at PATH to $TEST_ROOT/seen.json.
# Each test's Claude config folder (CLAUDE_CONFIG_DIR, set by vbw_setup) is
# inside its own TEST_ROOT, so the slot store under test is never the host's.

machine_setup() {
  vbw_setup
  local bin="$TEST_ROOT/bin" tool
  mkdir -p "$bin"
  for tool in getconf nproc sysctl; do
    cat > "$bin/$tool" << 'SH'
#!/bin/sh
n=$(cat "$TEST_ROOT/cores")
[ "$n" != none ] || exit 1
printf '%s\n' "$n"
SH
    chmod +x "$bin/$tool"
  done
  PATH="$bin:$PATH"
  export PATH
  cores 4
  LOG="$TEST_ROOT/units.log"
  : > "$LOG"
  OTHER="$TEST_ROOT/other project"
  THIRD="$TEST_ROOT/third project"
  export LOG OTHER THIRD
}

machine_teardown() {
  local pid
  # Runs a failed test started in the background and never waited for.
  for pid in $(jobs -p); do kill "$pid" 2> /dev/null || true; done
  wait 2> /dev/null || true
  [ -z "${TEST_ROOT:-}" ] || chmod -R u+rwx "$TEST_ROOT" 2> /dev/null || true
  vbw_teardown
}

# cores N: the computer reports N processor cores ("none": it cannot be read).
cores() { printf '%s\n' "$1" > "$TEST_ROOT/cores"; }

# machine_project DIR LABEL N [NAP [EXTRA]]: a VBW project in DIR (created when
# missing; files already in it are committed too) with checks C1..CN of R1, each
# running tests/unit.sh "LABEL-Ci" NAP 0, plus the EXTRA checks (a JSON array).
# Its one plan is done and its fix F1 of R1 is open, so vbw fix done F1 runs
# every check. SPEC_MORE (text) is appended to its spec. Approved and committed.
machine_project() {
  local dir="$1" label="$2" n="$3" nap="${4:-1}" extra="${5:-[]}" checks='[]' i
  for ((i = 1; i <= n; i++)); do
    checks=$(printf '%s' "$checks" | jq -c --arg id "C$i" --arg name "$label-C$i" --arg nap "$nap" \
      '. + [{id: $id, req: "R1", run: ["sh", "tests/unit.sh", $name, $nap, "0"], files: ["tests/unit.sh"]}]')
  done
  checks=$(printf '%s' "$checks" | jq -c --argjson x "$extra" '. + $x')
  mkdir -p "$dir"
  (
    set -e
    cd "$dir"
    [ -d .git ] || vbw_git_project
    "$VBW" init > /dev/null
    mkdir -p src tests
    printf 'paid\n' > src/pay.txt
    cat > tests/unit.sh << 'SH'
# tests/unit.sh NAME SECONDS CODE: logs its start, works SECONDS, logs its end, exits CODE.
printf 'start %s %s\n' "$(date +%s)" "$1" >> "$LOG"
sleep "$2"
printf 'end %s %s\n' "$(date +%s)" "$1" >> "$LOG"
echo "unit $1 done"
exit "$3"
SH
    cat > tests/peek.sh << 'SH'
# tests/peek.sh PATH: copies the slot store at PATH, as this unit sees it, to $TEST_ROOT/seen.json.
cp "$1" "$TEST_ROOT/seen.json"
SH
    printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n%s' "${SPEC_MORE:-}" > .vbw/spec.md
    "$VBW" spec sync > /dev/null
    jq --argjson c "$checks" '.checks = $c
      | .phases = [{id: "P1", title: "Pay", reqs: ["R1"], milestone: "M1"}]
      | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], status: "done"}]
      | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]
      | del(.requirements[]?.rules)
      | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end' \
      .vbw/record.json > "$TEST_ROOT/edit.json"
    cp "$TEST_ROOT/edit.json" .vbw/record.json
    git add -A
    git commit -q -m "chore(vbw): plan"
    "$VBW" approve > /dev/null
  )
}

# peek_check ID PATH: the JSON array of one check ID of R1 that peeks at the store at PATH.
peek_check() {
  jq -nc --arg id "$1" --arg p "$2" '[{id: $id, req: "R1", run: ["sh", "tests/peek.sh", $p], files: ["tests/peek.sh"]}]'
}

# seen_store: a unit saw a slot store, and it was JSON.
seen_store() {
  [ -f "$TEST_ROOT/seen.json" ] || { echo "no unit saw a slot store"; return 1; }
  jq -e . "$TEST_ROOT/seen.json" > /dev/null || { echo "the store a unit saw is not JSON:"; cat "$TEST_ROOT/seen.json"; return 1; }
}

# within SECONDS CMD...: run CMD, stopped by SIGALRM after SECONDS (a run that
# would wait forever fails instead of hanging the suite).
within() {
  perl -e '$SIG{ALRM} = "DEFAULT"; alarm shift @ARGV; exec { $ARGV[0] } @ARGV or die "cannot run $ARGV[0]\n"' "$@"
}

# bg DIR OUT ARGS...: start vbw ARGS in DIR in the background (stopped after
# 300 s), output to OUT; BG_PID is the vbw process itself.
bg() {
  local dir="$1" out="$2"
  shift 2
  (cd "$dir" && exec perl -e '$SIG{ALRM} = "DEFAULT"; alarm 300; exec { $ARGV[0] } @ARGV or die "cannot run $ARGV[0]\n"' "$VBW" "$@") \
    > "$out" 2>&1 < /dev/null 3>&- &
  # shellcheck disable=SC2034 # read by the tests that load this helper
  BG_PID=$!
}

# wait_ok PID...: wait for every PID; fails when any exited non-zero.
wait_ok() {
  local pid code=0
  for pid in "$@"; do wait "$pid" || code=1; done
  return "$code"
}

# peak: the most units running at the same moment, from the log's order.
peak() { awk '$1 == "start" { n++; if (n > m) m = n } $1 == "end" { n-- } END { print m + 0 }' "$LOG"; }

# starts [PREFIX]: how many units started (whose name starts with PREFIX).
starts() { awk -v p="${1:-}" '$1 == "start" && index($3, p) == 1 { n++ } END { print n + 0 }' "$LOG"; }

# start_line NAME / end_line NAME: the log line number of NAME's first start or end (empty: none).
start_line() { awk -v u="$1" '$1 == "start" && $3 == u { print NR; exit }' "$LOG"; }
end_line() { awk -v u="$1" '$1 == "end" && $3 == u { print NR; exit }' "$LOG"; }

# nth_start K PREFIX: the log line number of the K-th start of a unit whose name starts with PREFIX.
nth_start() { awk -v k="$1" -v p="$2" '$1 == "start" && index($3, p) == 1 && ++n == k { print NR; exit }' "$LOG"; }

# wait_starts N [PREFIX]: wait (up to 30 s) until N units (named PREFIX...) have started.
wait_starts() {
  local i
  for ((i = 0; i < 300; i++)); do
    [ "$(starts "${2:-}")" -lt "$1" ] || return 0
    sleep 0.1
  done
  echo "fewer than $1 units ${2:-}* started in 30 s"
  cat "$LOG"
  return 1
}

# wait_in_store PID: wait (up to 30 s) until the slot store names the run PID
# (a vbw process) anywhere among its values: the run holds or waits for a slot.
wait_in_store() {
  local i store="$CLAUDE_CONFIG_DIR/vbw/slots.json"
  for ((i = 0; i < 300; i++)); do
    jq -e --arg p "$1" 'any(.. | scalars; tostring == $p)' "$store" > /dev/null 2>&1 && return 0
    sleep 0.1
  done
  echo "the slot store never named run $1"
  cat "$store" 2> /dev/null
  return 1
}

# show: everything a failing test needs to see.
show() {
  local f
  echo "--- log"
  cat "$LOG"
  for f in "$TEST_ROOT"/*.out; do
    [ -f "$f" ] || continue
    echo "--- $f"
    cat "$f"
  done
}
