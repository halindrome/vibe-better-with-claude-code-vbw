#!/usr/bin/env bats
# R176 (docs/proof.md): vbw fix done tells, line by line and in totals, what it
# ran and what it reused. One line per check that ran, in the proof summary's
# form (id, status, seconds, "ran: <reason>"; a failing one adds the last line of
# its output); a reused check keeps its line with the time of the pass it
# reused; then the two count lines "checks: N ran, M reused" and "test files:
# N ran, M reused", printed every time (as 0 ran, 0 reused when nothing was
# judged). A cause (R168) prints once as "every candidate check runs: <cause>"
# and the counts stay true. Closing outcomes and the exit code are unchanged.
# Checks log their runs to $RANLOG. L1.

load helper
load fixture-helper

# The built shop with three open fixes, approved, built once per file.
setup_file() { fixture_build shop shop_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

shop_project() {
  vbw_setup
  vbw_git_project
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'echo C1 >> "$RANLOG"\ngrep -qx paid src/pay.txt || { echo "pay broken"; exit 1; }\n' > tests/pay.sh
  printf 'echo C2 >> "$RANLOG"\ngrep -qx sent src/receipt.txt || { echo "receipt broken"; exit 1; }\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Checkout", reqs: ["R1", "R2", "R3"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt", "src/pay.txt"]},
            {id: "P1.3", phase: "P1", title: "Look", reqs: ["R3"], files: ["src/ui.txt", "src/pay.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}]}' | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt && printf 'ui\n' > src/ui.txt
  git add -A && git commit -q -m "feat: built"
  edit_record '.plans[].status = "done"
    | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "a"},
                {id: "F2", req: "R2", attempts: 0, status: "open", note: "b"},
                {id: "F3", req: "R3", attempts: 0, status: "open", note: "c"}]'
  "$VBW" approve > /dev/null
}

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# line REGEX: exactly one line of $output matches REGEX.
line() {
  local n
  n=$(printf '%s\n' "$output" | grep -cE -- "$1" || true)
  [ "$n" -eq 1 ] || { echo "expected one line matching $1, found $n in:"; echo "$output"; false; }
}

@test "R176: a cause runs every candidate: the cause line prints once, one line per check that ran, then both count lines with the true numbers" {
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line '^every candidate check runs: this clone has no earlier recorded run$'
  line '^C1 pass [0-9.]+s$'
  line '^C2 pass [0-9.]+s$'
  line '^checks: 2 ran, 0 reused$'
  line '^test files: 0 ran, 0 reused$'
  [ "$(ran)" = "C1 C2 " ] || { echo "ran: $(ran)"; false; }
}

@test "R176: a check that ran says why in the proof summary's form; a reused check keeps its line with the time of the pass it reused" {
  local before after at
  before=$(now)
  "$VBW" fix done F1 > /dev/null
  after=$(now)
  : > "$RANLOG"
  printf 'paid\nmore\n' > src/pay.txt && git commit -q -am "fix: pay"
  vbw_run fix done F2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line '^C1 pass [0-9.]+s ran: src/pay\.txt changed$'
  at=$(printf '%s\n' "$output" | sed -n 's/^C2 unchanged since its pass (\([0-9TZ:-]*\))$/\1/p')
  [ -n "$at" ] || { echo "$output"; false; }
  [[ ! "$at" < "$before" && ! "$at" > "$after" ]] || { echo "$at is not the time of the pass ($before to $after)"; false; }
  line '^checks: 1 ran, 1 reused$'
  line '^test files: 0 ran, 0 reused$'
  printf '%s\n' "$output" | grep -qF 'every candidate' && { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; false; }
}

@test "R176: the count lines come after the per-unit lines" {
  "$VBW" fix done F1 > /dev/null
  printf 'paid\nmore\n' > src/pay.txt && git commit -q -am "fix: pay"
  vbw_run fix done F2
  local units counts
  units=$(printf '%s\n' "$output" | grep -nE '^C[12] ' | cut -d: -f1 | sort -n | tail -1)
  counts=$(printf '%s\n' "$output" | grep -nE '^checks: ' | cut -d: -f1)
  [ -n "$units" ] && [ -n "$counts" ] && [ "$units" -lt "$counts" ] || { echo "$output"; false; }
}

@test "R176: a failing check adds the last line of its output; the refusal and the exit code are unchanged" {
  "$VBW" fix done F1 > /dev/null
  printf 'broken\n' > src/pay.txt && git commit -q -am "fix: break"
  vbw_run fix done F2
  [ "$status" -eq 1 ]
  line '^C1 fail \(exit 1\) [0-9.]+s ran: src/pay\.txt changed: pay broken$'
  line '^checks: 1 ran, 1 reused$'
  [[ "$output" == *"F2 broke finished work"*"C1 fail"* ]] || { echo "$output"; false; }
  jq -e '(.fixes[] | select(.id == "F2")).status == "open"' .vbw/record.json
}

@test "R176: with nothing to judge the count lines still print, as 0 ran, 0 reused" {
  vbw_run fix done F9
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown fix F9"* ]] || { echo "$output"; false; }
  line '^checks: 0 ran, 0 reused$'
  line '^test files: 0 ran, 0 reused$'
  [ "$(ran)" = "" ]
}

@test "R176: closing outcomes are unchanged: fixed for a requirement proved by checks, closed for a [human] one" {
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line '^F1 fixed: vbw prove decides$'
  vbw_run fix done F3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line '^F3 closed: its requirement goes back to the user for acceptance$'
  line '^checks: 0 ran, 2 reused$'
  jq -e '(.fixes[] | select(.id == "F1")).status == "fixed" and (.fixes[] | select(.id == "F3")).status == "closed"' .vbw/record.json
}
