#!/usr/bin/env bats
# R148 (docs/proof.md): several VBW commands running checks at the same time in
# one project folder (parallel Devs each running vbw check, or vbw fix done
# beside vbw prove) share one limit: never more checks run together than
# check_jobs (or the machine default). A check that has to wait for a free
# slot waits instead of failing, and its timeout counts only from when it
# really starts. A slot held by a VBW process that died is freed. Checks
# marked alone still run with nothing else (R45). L1: checks that register
# themselves in $CONC and record how many are registered.

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
  cat > tests/conc.sh << 'SH'
touch "$CONC/run.$$"
ls "$CONC" | grep -c '^run\.' >> "$CONC/seen"
[ -z "$(ls "$CONC" | grep '^alone\.')" ] || echo "started beside an alone check" >> "$CONC/violation"
sleep "${NAP:-0.5}"
rm -f "$CONC/run.$$"
SH
  cat > tests/alone.sh << 'SH'
touch "$CONC/run.$$" "$CONC/alone.$$"
n=$(ls "$CONC" | grep -c '^run\.')
[ "$n" -eq 1 ] || echo "alone check ran beside $n" >> "$CONC/violation"
sleep 1
rm -f "$CONC/run.$$" "$CONC/alone.$$"
SH
  # long.sh holds its slot for LONG seconds and marks its start and end.
  cat > tests/long.sh << 'SH'
touch "$CONC/long.start"
sleep "${LONG:-3}"
touch "$CONC/long.end"
SH
  # short.sh records whether the long check had ended when it started.
  cat > tests/short.sh << 'SH'
if [ -e "$CONC/long.end" ]; then echo after > "$CONC/short"; else echo during > "$CONC/short"; fi
sleep 0.5
SH
}

teardown() {
  wait 2> /dev/null || true
  vbw_teardown
}

# project N [EXTRA_CHECKS_JSON]: checks C1..CN of R1 running tests/conc.sh,
# plus EXTRA; approved and committed.
project() {
  local i=1 checks='[]'
  while [ "$i" -le "$1" ]; do
    checks=$(printf '%s' "$checks" | jq -c --arg id "C$i" '. + [{id: $id, req: "R1", run: ["sh", "tests/conc.sh"], files: ["tests/conc.sh"]}]')
    i=$((i + 1))
  done
  checks=$(printf '%s' "$checks" | jq -c --argjson x "${2:-[]}" '. + $x')
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq --argjson c "$checks" '.checks = $c
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | .schema = (if any(.checks[]; .alone == true) then 2 else 1 end)
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

peak() { sort -n "$CONC/seen" | tail -n 1; }
seen() { wc -l < "$CONC/seen" | tr -d ' '; }

# together CMD...: each argument is one vbw command line (words split on
# spaces), all started at once in the background; waits for all; fails when any failed.
together() {
  local line pids=() pid code=0 n=0
  for line in "$@"; do
    n=$((n + 1))
    # shellcheck disable=SC2086 # a command line of several words on purpose
    "$VBW" $line > "$TEST_ROOT/out.$n" 2>&1 < /dev/null 3>&- &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid" || code=1; done
  [ "$code" -eq 0 ] || { cat "$TEST_ROOT"/out.*; return 1; }
}

@test "R148: three vbw check processes at once never run more checks together than check_jobs" {
  project 12
  "$VBW" config set check_jobs 2 > /dev/null
  together "check C1 C2 C3 C4" "check C5 C6 C7 C8" "check C9 C10 C11 C12"
  [ "$(seen)" = 12 ]
  [ "$(peak)" -le 2 ] || { echo "peak $(peak) with check_jobs 2"; false; }
}

@test "R148: vbw prove beside vbw check share the same limit" {
  project 10
  "$VBW" config set check_jobs 3 > /dev/null
  together "prove" "check C1 C2 C3 C4 C5" "check C6 C7 C8 C9 C10"
  [ "$(seen)" = 20 ]
  [ "$(peak)" -le 3 ] || { echo "peak $(peak) with check_jobs 3"; false; }
}

@test "R148: with check_jobs 1, only one check runs at a time across all processes" {
  project 6
  "$VBW" config set check_jobs 1 > /dev/null
  together "check C1 C2" "check C3 C4" "check C5 C6"
  [ "$(seen)" = 6 ]
  [ "$(peak)" = 1 ] || { echo "peak $(peak) with check_jobs 1"; false; }
}

@test "R148: a check waiting for a free slot waits instead of failing, and its timeout counts from its real start" {
  project 0 '[{"id":"C1","req":"R1","run":["sh","tests/long.sh"],"files":["tests/long.sh"]},
              {"id":"C2","req":"R1","run":["sh","tests/short.sh"],"files":["tests/short.sh"],"timeout":2}]'
  "$VBW" config set check_jobs 1 > /dev/null
  LONG=4 "$VBW" check C1 > "$TEST_ROOT/o1" 2>&1 < /dev/null 3>&- &
  local holder=$! i
  for i in $(seq 1 100); do [ -e "$CONC/long.start" ] && break; sleep 0.1; done
  [ -e "$CONC/long.start" ]
  vbw_run check C2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"C2 pass"* ]] || { echo "$output"; false; }
  [ "$(cat "$CONC/short")" = after ] || { echo "C2 started while C1 held the only slot"; false; }
  wait "$holder"
}

@test "R148: a slot held by a VBW process that died is freed, so later checks do not wait for it" {
  project 0 '[{"id":"C1","req":"R1","run":["sh","tests/long.sh"],"files":["tests/long.sh"]},
              {"id":"C2","req":"R1","run":["sh","tests/short.sh"],"files":["tests/short.sh"]}]'
  "$VBW" config set check_jobs 1 > /dev/null
  LONG=20 "$VBW" check C1 > "$TEST_ROOT/o1" 2>&1 < /dev/null 3>&- &
  local holder=$! i start
  for i in $(seq 1 100); do [ -e "$CONC/long.start" ] && break; sleep 0.1; done
  [ -e "$CONC/long.start" ]
  # The VBW process dies without cleaning up; its check runs on, orphaned.
  kill -KILL "$holder"
  wait "$holder" 2> /dev/null || true
  start=$(date +%s)
  vbw_run check C2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ $(($(date +%s) - start)) -lt 12 ] || { echo "C2 waited for the dead process's slot"; false; }
}

@test "R148: a check marked alone still runs with nothing else beside checks from other processes (R45)" {
  project 8 '[{"id":"C9","req":"R1","run":["sh","tests/alone.sh"],"files":["tests/alone.sh"],"alone":true}]'
  "$VBW" config set check_jobs 4 > /dev/null
  together "check C1 C2 C3 C4" "check C9" "check C5 C6 C7 C8"
  [ ! -s "$CONC/violation" ] || { cat "$CONC/violation"; false; }
  [ "$(peak)" -le 4 ] || { echo "peak $(peak) with check_jobs 4"; false; }
}
