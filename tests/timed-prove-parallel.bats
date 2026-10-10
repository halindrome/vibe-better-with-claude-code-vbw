#!/usr/bin/env bats
# R69, R152 (docs/proof.md): the time of a proof of many checks, measured in
# the release run (tests/timed-*.bats), never in vbw prove: 24 checks of one
# second each finish in under 24 s, which one after another could not.
# Fixture as in tests/prove-parallel.bats.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  local tool
  mkdir -p "$TEST_ROOT/bin"
  for tool in getconf nproc sysctl; do
    printf '#!/bin/sh\necho 6\n' > "$TEST_ROOT/bin/$tool"
    chmod +x "$TEST_ROOT/bin/$tool"
  done
  PATH="$TEST_ROOT/bin:$PATH"
  export PATH
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  # Each check registers itself, records how many checks are registered
  # (itself included), waits, and unregisters. An alone check must be the only
  # one registered and no other check may start while it is registered.
  cat > tests/conc.sh << 'SH'
touch "$CONC/run.$$"
n=$(ls "$CONC" | grep -c '^run\.')
echo "$n" >> "$CONC/seen"
[ -z "$(ls "$CONC" | grep '^alone\.')" ] || echo "started beside an alone check" >> "$CONC/violation"
sleep "${NAP:-0.4}"
rm -f "$CONC/run.$$"
grep -qx paid src/pay.txt
SH
  cat > tests/alone.sh << 'SH'
touch "$CONC/run.$$" "$CONC/alone.$$"
n=$(ls "$CONC" | grep -c '^run\.')
[ "$n" -eq 1 ] || echo "alone check ran beside $n" >> "$CONC/violation"
sleep 0.4
rm -f "$CONC/run.$$" "$CONC/alone.$$"
SH
  cat > tests/bad.sh << 'SH'
echo "bad on purpose"
exit 3
SH
}

teardown() { vbw_teardown; }

# project N [ALONE_AT] [BAD_AT]: N checks C1..CN of R1; check ALONE_AT is alone,
# check BAD_AT fails; approved and committed.
project() {
  local n=$1 i checks='[]' run
  for i in $(seq 1 "$n"); do
    run='["sh","tests/conc.sh"]'
    [ "$i" = "${3:-}" ] && run='["sh","tests/bad.sh"]'
    [ "$i" = "${2:-}" ] && run='["sh","tests/alone.sh"]'
    checks=$(printf '%s' "$checks" | jq -c --arg id "C$i" --argjson run "$run" '. + [{id: $id, req: "R1", run: $run, files: ["tests/conc.sh", "tests/alone.sh", "tests/bad.sh"]}]')
  done
  if [ -n "${2:-}" ]; then checks=$(printf '%s' "$checks" | jq -c --arg id "C$2" 'map(if .id == $id then . + {alone: true} else . end)'); fi
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq --argjson c "$checks" '.checks = $c
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | .schema = (if any(.checks[]; .alone == true) then 2 else 1 end)
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

@test "R69: a proof of 24 checks of one second each finishes in under 24 s" {
  project 24
  # 24 checks of one second each take at least 24 s one after another, so any
  # proof under 24 s ran checks side by side. The bound is that floor, not a
  # guess of this machine's speed.
  NAP=1 run bash -c 'start=$(date +%s); "$1" prove > /dev/null; echo $(( $(date +%s) - start ))' _ "$VBW"
  [ "$status" -eq 0 ]
  [ "$output" -lt 24 ] || { echo "took $output s"; false; }
}
