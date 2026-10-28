#!/usr/bin/env bats
# R69 (2026-10-06, found by the Linux suite): the check gate's lock is never
# taken from a live owner. A waiting check that finds the lock's owner file
# empty (it was read while the owner released the lock and a new owner had not
# yet written it) retries; it does not treat the owner as dead and remove the
# lock, which deleted a fresh lock under a running proof ("mutex/pid: No such
# file or directory"). A lock with no owner is taken over only after a wait.
# A lock whose owner is gone is taken over by renaming its owner file, never by
# removing the folder, so of two runs that find the same dead owner only one
# wins, and neither removes a lock a third run took in between (T141).
# L1: the gate on a fixture.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p tests
  printf 'true\n' > tests/ok.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/ok.sh"], files:["tests/ok.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["tests/ok.sh"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

@test "R69: a lock whose owner file reads empty is not taken over at once: the check waits, then takes it over and runs" {
  mkdir -p .vbw/runtime/gate/mutex
  : > .vbw/runtime/gate/mutex/pid
  "$VBW" check C1 > "$TEST_ROOT/o1" 2>&1 < /dev/null 3>&- &
  local pid=$!
  sleep 1
  kill -0 "$pid"
  [ -d .vbw/runtime/gate/mutex ]
  local code=0
  wait "$pid" || code=$?
  [ "$code" -eq 0 ] || { cat "$TEST_ROOT/o1"; false; }
  grep -q 'C1 pass' "$TEST_ROOT/o1"
}

@test "R69: a lock with no owner left for long is taken over, and the check runs" {
  mkdir -p .vbw/runtime/gate/mutex
  run "$VBW" check C1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"C1 pass"* ]]
}

@test "R69: the owner write never prints an error when the lock vanished under it" {
  ! grep -nE 'printf .*> "\$g/mutex/pid"$' "$PLUGIN_ROOT/lib/checks.sh"
}

@test "T141: a gate lock whose dead owner two runs find is never taken from the run that took it over first" {
  sleep 0 & local dead=$!
  wait "$dead"
  sleep 120 & local live=$!
  mkdir -p .vbw/runtime/gate/mutex
  printf '%s\n' "$dead" > .vbw/runtime/gate/mutex/pid
  # The other run takes the lock over while this one is still judging its owner gone, and holds it:
  # this run must wait for it, never remove it, and enter once the other run lets go.
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/slots.sh"; . "$VBW_LIB/checks.sh"
    dead='"$dead"' live='"$live"' tries=0 fired=
    m="$VBW_RUNTIME/gate/mutex"
    checks_gate_live() {
      if [ "$1" = "x.$dead" ] && [ -z "$fired" ]; then
        fired=1; rm -rf "$m"; mkdir "$m"; printf "%s\n" "$live" > "$m/pid"
      fi
      [ "$1" != "x.$dead" ] && kill -0 "${1#x.}" 2> /dev/null
    }
    sleep() {
      local p=
      tries=$((tries + 1))
      { IFS= read -r p < "$m/pid"; } 2> /dev/null || true
      [ "$p" = "$live" ] || { echo "the run that held the gate lost it at try $tries"; exit 1; }
      [ "$tries" -lt 3 ] || rm -rf "$m"
    }
    CHECKS_LIMIT=4 checks_gate_enter C1 false || { echo "entering failed"; exit 1; }
    echo "entered after $tries tries"'
  kill "$live"; wait "$live" 2> /dev/null || true
  [ "$status" -eq 0 ] && [ "$output" = "entered after 3 tries" ] || { echo "$output"; false; }
}

@test "T180: a unit's entry at a free gate and its leave each spawn only one removal" {
  # Both lie between one unit giving its slot back and the next one taking it: a lock
  # folder made and removed there (mkdir, chmod, rm, rm, rmdir) kept slots idle.
  local bin="$TEST_ROOT/shim" t
  mkdir -p "$bin"
  for t in rm rmdir mkdir chmod mv ln cat touch; do
    printf '#!/bin/sh\necho %s >> "$TEST_ROOT/procs"\nexec %s "$@"\n' "$t" "$(command -v "$t")" > "$bin/$t"
    chmod +x "$bin/$t"
  done
  mkdir -p .vbw/runtime/gate
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  PATH="$bin:$PATH" run vbw_kernel '. "$VBW_LIB/slots.sh"; . "$VBW_LIB/checks.sh"
    : > "$TEST_ROOT/procs"
    CHECKS_LIMIT=4 checks_gate_enter C1 false || exit 1
    echo --- >> "$TEST_ROOT/procs"
    checks_gate_leave C1
    ls -A "$VBW_RUNTIME/gate"'
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; false; }
  [ "$(tr '\n' ' ' < "$TEST_ROOT/procs")" = "rm --- rm " ] || { tr '\n' ' ' < "$TEST_ROOT/procs"; false; }
}
