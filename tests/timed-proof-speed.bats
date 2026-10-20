#!/usr/bin/env bats
# R202 (docs/proof.md, D245): the time of VBW's own work in a proof, measured in
# the release run (tests/timed-*.bats), never in vbw prove. Builds the scaled-down
# stand-in with tools/measure-proof-speed.sh --generate, proves it, and reads
# evidence.own from the record: read tracking per unit that ran and planning
# stay under their limits. A machine too busy to measure is reported and skipped,
# like tools/bench-hooks.sh does.

load helper

TRACKING_PER_UNIT_LIMIT=1
PLANNING_LIMIT=5
STARTUP_LIMIT_MS=20
RUNS=20

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# startup_ms: the mean CPU ms of RUNS runs of sh -c 'jq -n empty' (bash's times).
startup_ms() {
  local i log="$TEST_ROOT/times.log"
  : > "$log"
  for ((i = 0; i < RUNS; i++)); do
    times >> "$log"
    sh -c 'jq -n empty' < /dev/null > /dev/null 2>&1 || true
    times >> "$log"
  done
  awk -v runs="$RUNS" '
    function sec(s) { sub(/s$/, "", s); split(s, p, "m"); return p[1] * 60 + p[2] }
    NR % 2 == 0 { t[++n] = sec($1) + sec($2) }
    END { for (k = 1; k + 1 <= n; k += 2) sum += t[k + 1] - t[k]
          printf "%.1f\n", sum * 1000 / runs }' "$log"
}

@test "R202: read tracking stays under 1 s per unit and planning under 5 s on the scaled-down stand-in" {
  local startup
  startup=$(startup_ms)
  if awk -v a="$startup" -v b="$STARTUP_LIMIT_MS" 'BEGIN { exit !(a + 0 > b + 0) }'; then
    echo "machine too busy to measure: sh and jq startup takes $startup ms CPU per call, above $STARTUP_LIMIT_MS ms; nothing judged"
    skip "machine too busy to measure"
  fi
  local proj="$TEST_ROOT/stand-in" out ran tracking planning
  bash "$REPO_ROOT/tools/measure-proof-speed.sh" --generate "$proj" --files 2000 --folders 300 --units 40 > /dev/null
  cd "$proj"
  out=$("$VBW" prove < /dev/null 2>&1) || { echo "$out"; false; }
  ran=$(printf '%s\n' "$out" | sed -nE 's/^ran again: ([0-9]+) of [0-9]+ units.*/\1/p' | head -n 1)
  [ -n "$ran" ] && [ "$ran" -gt 0 ] || { echo "no 'ran again' line with units that ran:"; echo "$out"; false; }
  tracking=$(jq '.evidence.own.tracking' .vbw/record.json)
  planning=$(jq '.evidence.own.planning' .vbw/record.json)
  echo "read tracking $tracking s over $ran units, planning $planning s"
  awk -v t="$tracking" -v n="$ran" -v l="$TRACKING_PER_UNIT_LIMIT" 'BEGIN { exit !(t / n <= l) }' \
    || { echo "read tracking $tracking s over $ran units exceeds $TRACKING_PER_UNIT_LIMIT s per unit"; false; }
  awk -v p="$planning" -v l="$PLANNING_LIMIT" 'BEGIN { exit !(p + 0 <= l) }' \
    || { echo "planning $planning s exceeds $PLANNING_LIMIT s"; false; }
}
