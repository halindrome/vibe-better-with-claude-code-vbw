#!/usr/bin/env bats
# The store of recorded runs ($(git common dir)/vbw/runs.json) holds every unit's
# read list, so it can reach hundreds of MB, and jq needs a few times its size in
# memory to load it. Only the work that needs the read lists loads it: the reuse
# planning and the save. A time estimate needs each unit's last seconds alone,
# and reads them from the small file the save writes beside the store
# (run-times.json): the proof's note as its units finish, vbw next and vbw
# status. (2026-10-28, a field report: a 669 MB store was loaded again for every
# unit a proof finished, up to 10 copies of about 1.8 GB at once, until the
# computer ran out of memory.) L1.
#
# A stand-in for jq first on PATH writes "store" to a log for every jq run given
# the store and "times" for every one given the times; each unit writes "unit"
# to the same log, so the log shows what was read while the units ran.

load helper
load step-helper
load road-helper
load fixture-helper

# 12 checks, each running tests/late.sh; the store and the times know each
# unit's last run (fingerprints that match nothing, so every unit runs); three
# earlier proofs timed C1 and C2.
built_project() {
  vbw_setup
  step_project
  mkdir -p tests
  # late.sh: logs itself, then moves the proof's start 10 min back, so the proof
  # runs late and every finished unit moves its end (and the milestone's).
  cat > tests/late.sh << 'SH'
echo unit >> "$LOG"
jq '.started_at |= (fromdateiso8601 - 600 | todateiso8601)' "$NOTE" > "$NOTE.late" && mv "$NOTE.late" "$NOTE"
SH
  step_edit '.plans[].status = "done" | .checks = [range(1; 13) | {id: "C\(.)", req: "R1", run: ["sh", "tests/late.sh"], files: ["tests/late.sh"]}]'
  git add -A && git commit -q -m "chore(vbw): checks"
  "$VBW" approve > /dev/null
  runs_seed "$(jq -nc '[range(1; 13) | {key: "check:C\(.)", value: .}] | from_entries')"
  hist_proof '[{"name": "check:C1", "seconds": 1}, {"name": "check:C2", "seconds": 2}]' 3 3
  "$VBW" config set check_jobs 1 > /dev/null
}
setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
  local real
  real=$(command -v jq)
  mkdir -p "$TEST_ROOT/bin"
  printf '#!/bin/sh\nfor a in "$@"; do\n  case "$a" in\n    */vbw/runs.json) echo store >> "$LOG" ;;\n    */vbw/run-times.json) echo times >> "$LOG" ;;\n  esac\ndone\nexec "%s" "$@"\n' "$real" > "$TEST_ROOT/bin/jq"
  chmod +x "$TEST_ROOT/bin/jq"
  LOG="$TEST_ROOT/log"
  PATH="$TEST_ROOT/bin:$PATH"
  export LOG PATH
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# between: the log's lines from the first unit to the last.
between() {
  local first last
  first=$(grep -n '^unit$' "$LOG" | head -1 | cut -d: -f1)
  last=$(grep -n '^unit$' "$LOG" | tail -1 | cut -d: -f1)
  sed -n "${first},${last}p" "$LOG"
}

@test "a proof of many units never loads the store while its units run; their updates read the times" {
  : > "$LOG"
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 < /dev/null || { cat "$TEST_ROOT/prove.out"; false; }
  [ "$(grep -c '^unit$' "$LOG")" -eq 12 ] || { cat "$LOG"; false; }
  [ "$(between | grep -c '^store$')" -eq 0 ] || { echo "the store was loaded while the units ran:"; cat "$LOG"; false; }
  # Every unit's update moved the end, so the estimate ran: from the times alone.
  [ "$(between | grep -c '^times$')" -ge 1 ] || { cat "$LOG"; false; }
}

@test "vbw next and vbw status time the proof from the times, never from the store" {
  # The first answer plans the proof (that reads the store) and caches the plan.
  "$VBW" next --json > /dev/null
  : > "$LOG"
  local s
  s=$("$VBW" next --json | jq -c '.step')
  "$VBW" status > /dev/null
  "$VBW" status --json > /dev/null
  [ "$(grep -c '^store$' "$LOG")" -eq 0 ] || { echo "the store was loaded for an estimate:"; cat "$LOG"; false; }
  grep -q '^times$' "$LOG" || { cat "$LOG"; false; }
  # The units' last seconds still count: C1..C12 last took 1..12 s, the history at most
  # C1 1 s and C2 2 s; 78 s of units at the learned ratio 3 / 3 = 1.
  printf '%s' "$s" | jq -e '.kind == "proof" and .parts == 12 and .seconds == 78' || { echo "$s"; false; }
}
