#!/usr/bin/env bats
# R166 (docs/proof.md): the wiring of vbw prove and vbw fix done to the one
# reuse rule. vbw prove tests the file system first, plans every check and
# project command with the rule, runs what must run in clean slot copies, and
# saves results and read lists in the clone's store (never in the record);
# where reads cannot be recorded it reuses nothing, saves no read list and says
# so. The evidence is full only when nothing was reused, a reused line names
# the proof it came from, a line that ran says why, and "checks: N ran, M
# reused" is printed on every proof. vbw fix done takes the checks of every
# finished requirement as candidates, picks the ones to run with the same rule,
# runs them in clean copies, and fails the fixes whose files serve a failing
# check, or every named fix when it serves none. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  export RANLOG="$TEST_ROOT/ran.log"
  printf 'paid\n' > src/pay.txt
  printf 'sent\n' > src/receipt.txt
  printf 'unread\n' > src/other.txt
  printf 'echo C1 >> "$RANLOG"\npwd > "$TEST_ROOT/c1.pwd"\ngrep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'echo C2 >> "$RANLOG"\ngrep -qx sent src/receipt.txt\n' > tests/receipt.sh
  printf 'echo all >> "$RANLOG"\ngrep -qx paid src/pay.txt\n' > tests/all.sh
  git add -A && git commit -q -m "chore: files"
  printf '%s' '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1", "R2"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]},
              {"id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" plan "done" P1.1 > /dev/null 2>&1 || true
  "$VBW" plan "done" P1.2 > /dev/null 2>&1 || true
  git add -A && git commit -q -m "chore(vbw): plan" || true
  STORE="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  export STORE
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$RANLOG"
}

teardown() { vbw_teardown; }

ran() { sort "$RANLOG" | tr '\n' ' '; }

change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "chore: change $1"
}

line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

no_reads() {
  local real
  real=$(command -v touch)
  mkdir -p "$TEST_ROOT/noreads"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -*a*) exit 0 ;; esac; done\nexec %s "$@"\n' "$real" > "$TEST_ROOT/noreads/touch"
  chmod +x "$TEST_ROOT/noreads/touch"
}

@test "R166: a proof saves the read list of every check and project command in the store, and none in the record" {
  jq -e '.runs["check:C1"].reads | index("src/pay.txt") != null' "$STORE"
  jq -e '.runs["check:C2"].reads | index("src/receipt.txt") != null' "$STORE"
  jq -e '.runs["command:test"].reads | index("src/pay.txt") != null' "$STORE"
  [ "$(jq '[.evidence.checks[], .evidence.commands[] | select(has("reads") or has("dirs") or has("git"))] | length' .vbw/record.json)" -eq 0 ]
}

@test "R166: a check runs in a clean copy of the committed code, not in the working folder" {
  [ "$(basename "$(cat "$TEST_ROOT/c1.pwd")")" = tree ]
}

@test "R166: a change to a file no check or command read reuses everything, and every proof prints both counts" {
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  [[ "$output" == *"checks: 0 ran, 2 reused"* ]] || { echo "$output"; false; }
  line test | grep -q 'reused (proof of ' || { echo "$output"; false; }
  jq -e '.evidence.full == false and .evidence.commands.test.reused == true' .vbw/record.json
}

@test "R166: a change to a file a check and the test command read runs both and nobody else, each saying why" {
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 all " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C1 | grep -qE 'ran: src/pay\.txt changed' || { echo "$output"; false; }
  line test | grep -qE 'ran: src/pay\.txt changed' || { echo "$output"; false; }
  line C2 | grep -q 'reused (proof of ' || { echo "$output"; false; }
  [[ "$output" == *"checks: 1 ran, 1 reused"* ]] || { echo "$output"; false; }
}

@test "R166: a reused line keeps the time of the proof that really ran it, across proofs" {
  local first
  first=$(jq -r '.evidence.at' .vbw/record.json)
  change src/other.txt
  "$VBW" prove > /dev/null
  change src/other.txt
  vbw_run prove
  line C2 | grep -qF "reused (proof of $first)" || { echo "$first"; echo "$output"; false; }
}

@test "R166: vbw prove --full runs everything, is recorded as full and still prints the counts" {
  change src/other.txt
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 all " ] || { echo "ran: $(ran)"; false; }
  [[ "$output" == *"checks: 2 ran, 0 reused"* ]] || { echo "$output"; false; }
  jq -e '.evidence.full == true and all(.evidence.checks[]; (.reused // false) == false)' .vbw/record.json
}

@test "R166: where the file system records no reads nothing is reused, no read list is saved and the summary says so" {
  no_reads
  change src/other.txt
  PATH="$TEST_ROOT/noreads:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 all " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF '  ran everything: this file system does not record which files are read' || { echo "$output"; false; }
  jq -e 'all(.runs[]; .reads == null)' "$STORE"
  jq -e '.evidence.full == true' .vbw/record.json
}

@test "R166: a failed check is run again by the next proof even when nothing it read changed" {
  printf 'echo C3 >> "$RANLOG"\nexit 1\n' > tests/never.sh
  git add tests/never.sh && git commit -q -m "chore: never"
  jq '.checks += [{id: "C3", req: "R2", run: ["sh", "tests/never.sh"], files: ["tests/never.sh"]}] | .protected = ([.checks[].files // [] | .[]] | unique)' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git commit -q -am "chore(vbw): C3"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || true
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$(ran)" = "C3 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C3 | grep -q 'ran: last result failed' || { echo "$output"; false; }
}

# done_fix: open fix F1 for R2 (its files: src/receipt.txt), committed.
open_fix() {
  jq '.fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "receipt"}]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git commit -q -am "chore(vbw): fix F1"
}

@test "R166: vbw fix done takes the checks of every finished requirement as candidates, reuses the unchanged ones and saves read lists" {
  open_fix
  change src/pay.txt
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^C2 unchanged since its pass \(' || { echo "$output"; false; }
  jq -e '.runs["check:C1"].tree != null' "$STORE"
}

@test "R166: vbw fix done right after a passing proof reuses every unchanged check: nothing committed is vbw prove's cause alone" {
  open_fix
  git commit -q --allow-empty -m "chore(vbw): proof passed"
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^C1 unchanged since its pass \(' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^C2 unchanged since its pass \(' || { echo "$output"; false; }
  [[ "$output" != *"every candidate check runs"* ]] || { echo "$output"; false; }
}

@test "R166: vbw fix done runs its checks in clean copies" {
  open_fix
  change src/pay.txt
  "$VBW" fix "done" F1 > /dev/null
  [ "$(basename "$(cat "$TEST_ROOT/c1.pwd")")" = tree ]
}

@test "R166: a failing check that no named fix's files serve fails every named fix" {
  open_fix
  printf 'wrong\n' > src/pay.txt
  git commit -q -am "fix: break pay"
  vbw_run fix "done" F1
  [ "$status" -ne 0 ]
  [[ "$output" == *"F1 broke finished work"* && "$output" == *"C1 fail"* ]] || { echo "$output"; false; }
  jq -e '[.fixes[] | select(.id == "F1")][0].status == "open"' .vbw/record.json
}

@test "R166: a failing check that a named fix's files serve fails that fix and not another" {
  jq '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "pay"}, {id: "F2", req: "R2", attempts: 0, status: "open", note: "receipt"}]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git commit -q -am "chore(vbw): fixes"
  printf 'wrong\n' > src/pay.txt
  git commit -q -am "fix: break pay"
  vbw_run fix "done" F1 F2
  [ "$status" -ne 0 ]
  jq -e '([.fixes[] | select(.id == "F1")][0].status == "open") and ([.fixes[] | select(.id == "F2")][0].status == "fixed")' .vbw/record.json || { echo "$output"; false; }
}
