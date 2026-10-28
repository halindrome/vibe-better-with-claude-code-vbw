#!/usr/bin/env bats
# R148, F107 (docs/proof.md): during one run of several checks the check_jobs
# limit is read once, so a check that raises check_jobs while it runs does not
# raise how many checks that run lets run at once. Regression test for the fix
# that hands the limit read by checks_run_all to the gate (CHECKS_LIMIT). L1:
# order evidence only (marker files in $CONC), never timing. The run reads
# check_jobs 1; its first check raises it to 3; another vbw process, started
# after the raise, holds a slot; the run's next check must wait for that slot.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  # raise.sh: raises check_jobs to 3 while it runs, then stays until the test says go.
  cat > tests/raise.sh << 'SH'
"$VBW" config set check_jobs 3 > /dev/null 2>&1 || echo "could not raise check_jobs" >> "$CONC/violation"
touch "$CONC/raised"
i=0
while [ ! -e "$CONC/go" ] && [ "$i" -lt 300 ]; do
  sleep 0.1
  i=$((i + 1))
done
SH
  # hold.sh (another vbw process): holds a slot until next.sh has started, or
  # about 5 seconds have passed; hold.running exists while it holds.
  cat > tests/hold.sh << 'SH'
touch "$CONC/hold.running"
i=0
while [ ! -e "$CONC/next.start" ] && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
rm -f "$CONC/hold.running"
SH
  # next.sh: records whether the other process's check still held its slot when it started.
  cat > tests/next.sh << 'SH'
if [ -e "$CONC/hold.running" ]; then echo during > "$CONC/next"; else echo after > "$CONC/next"; fi
touch "$CONC/next.start"
SH
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/raise.sh"], files:["tests/raise.sh"]},
                 {id:"C2", req:"R1", run:["sh","tests/next.sh"], files:["tests/next.sh"]},
                 {id:"C3", req:"R1", run:["sh","tests/hold.sh"], files:["tests/hold.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() {
  touch "$CONC/go" "$CONC/next.start" 2> /dev/null || true
  wait 2> /dev/null || true
  vbw_teardown
}

# until_file PATH: wait for PATH to exist (at most about 10 seconds).
until_file() {
  local _
  for _ in $(seq 1 100); do
    [ -e "$1" ] && return 0
    sleep 0.1
  done
  echo "never appeared: $1"
  return 1
}

@test "R148: a check that raises check_jobs during a run does not raise how many checks that run lets run at once" {
  "$VBW" config set check_jobs 1 > /dev/null
  # The run reads check_jobs 1; its first check C1 raises it to 3 while it runs.
  "$VBW" check C1 C2 > "$TEST_ROOT/run.out" 2>&1 < /dev/null 3>&- &
  local run=$!
  until_file "$CONC/raised"
  # A later vbw process reads 3 and takes a slot beside C1.
  "$VBW" check C3 > "$TEST_ROOT/hold.out" 2>&1 < /dev/null 3>&- &
  local holder=$!
  until_file "$CONC/hold.running"
  touch "$CONC/go"
  wait "$run" || {
    cat "$TEST_ROOT/run.out"
    false
  }
  wait "$holder" || {
    cat "$TEST_ROOT/hold.out"
    false
  }
  [ ! -s "$CONC/violation" ] || {
    cat "$CONC/violation"
    false
  }
  "$VBW" config < /dev/null | grep -q '^check_jobs: 3 (set' || {
    echo "C1 did not raise check_jobs"
    false
  }
  grep -q 'C2 pass' "$TEST_ROOT/run.out" || {
    cat "$TEST_ROOT/run.out"
    false
  }
  [ "$(cat "$CONC/next")" = after ] || {
    echo "C2 started beside the other process's check: the run used the check_jobs C1 raised (read once: 1)"
    false
  }
}
