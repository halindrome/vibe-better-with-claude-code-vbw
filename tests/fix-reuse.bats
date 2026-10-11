#!/usr/bin/env bats
# R43 (docs/proof.md, D260): vbw fix done does not rerun a check whose last
# pass is still good under the one reuse rule vbw prove uses: its approved
# definition is unchanged and no file it read in that passing run (its read
# list) changed since. It says the check is unchanged since its pass, with the
# time of that pass. Checks run on a clean copy of the committed code. Passes
# and read lists are kept in this clone's store of recorded runs
# (vbw/runs.json in its git directory), never in the record: an older VBW still
# reads the record, and closing a fix leaves no record change. vbw prove and
# vbw fix done share the store and the rule. Checks count their runs in $RUNS.

load helper

setup() {
  vbw_setup
  vbw_git_project
  export RUNS="$TEST_ROOT/runs"
  mkdir -p "$RUNS" "$TEST_ROOT/bin"
  # C3 declares no files; it reads src/ui.txt from the project it runs in.
  printf 'echo run >> "$RUNS/$1"\ncat src/ui.txt > /dev/null\n' > "$TEST_ROOT/bin/count.sh"
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'echo run >> "$RUNS/C1"\ngrep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'echo run >> "$RUNS/C2"\ngrep -qx sent src/receipt.txt\n' > tests/receipt.sh
  PLAN=$(jq -n --arg c "$TEST_ROOT/bin/count.sh" '{phases: [{id: "P1", title: "Checkout", reqs: ["R1", "R2", "R3"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt", "src/pay.txt"]},
            {id: "P1.3", phase: "P1", title: "Look", reqs: ["R3"], files: ["src/ui.txt", "src/pay.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R1", run: ["sh", $c, "C3"]}]}')
  printf '%s' "$PLAN" | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt && printf 'ui\n' > src/ui.txt
  git add -A && git commit -q -m "feat: built"
  edit_record '.plans[].status = "done"
    | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "a"},
                {id: "F2", req: "R2", attempts: 0, status: "open", note: "b"},
                {id: "F3", req: "R3", attempts: 0, status: "open", note: "c"}]'
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# store: this clone's store of recorded runs.
store() { printf '%s/vbw/runs.json' "$(git rev-parse --path-format=absolute --git-common-dir)"; }

# in_store PATH: the store holds PATH (in a read list) as a value.
in_store() { jq -e --arg p "$1" 'any(.. | strings; . == $p or endswith("/" + $p))' "$(store)" > /dev/null; }

# runs ID: how many times the check ran.
runs() { if [ -f "$RUNS/$1" ]; then wc -l < "$RUNS/$1" | tr -d ' '; else printf 0; fi; }

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

@test "a passing check is kept in the clone's store of recorded runs with the files it read, never in the record" {
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 1 ]
  [ -f "$(store)" ] || { echo "no store at $(store)"; false; }
  in_store src/pay.txt || { cat "$(store)"; false; }
  in_store src/receipt.txt || { cat "$(store)"; false; }
  in_store src/ui.txt || { cat "$(store)"; false; }
  jq -e 'has("passes") or has("runs") | not' .vbw/record.json
}

@test "an unchanged pass is not rerun, and the output says so with the time of the pass" {
  local before after at
  before=$(now)
  "$VBW" fix done F1 > /dev/null
  after=$(now)
  vbw_run fix done F2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ] || { echo "C1 $(runs C1) C2 $(runs C2) C3 $(runs C3)"; echo "$output"; false; }
  at=$(printf '%s\n' "$output" | sed -n 's/^C1 unchanged since its pass (\([0-9TZ:-]*\))$/\1/p')
  [ -n "$at" ] || { echo "$output"; false; }
  [[ ! "$at" < "$before" && ! "$at" > "$after" ]] || { echo "$at is not the time of the pass ($before to $after)"; false; }
  [[ "$output" == *"C2 unchanged since its pass"* ]]
  [[ "$output" == *"C3 unchanged since its pass"* ]]
  jq -e '(.fixes[] | select(.id == "F2")).status == "fixed"' .vbw/record.json
}

@test "a committed change to a file a check read reruns that check, and only that check" {
  "$VBW" fix done F1 > /dev/null
  printf 'more\n' >> src/pay.txt && git commit -q -am "fix: pay"
  vbw_run fix done F2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 2 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ] || { echo "C1 $(runs C1) C2 $(runs C2) C3 $(runs C3)"; echo "$output"; false; }
  [[ "$output" != *"C1 unchanged"* ]]
  [[ "$output" == *"C2 unchanged since its pass"* ]]
}

@test "a changed approved definition reruns that check, and a check whose definition is unchanged is reused though the contract changed" {
  "$VBW" fix done F1 > /dev/null
  printf '%s' "$PLAN" | jq '.checks[0].timeout = 100' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  vbw_run fix done F2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 2 ]
  [[ "$output" != *"C1 unchanged"* ]]
  [ "$(runs C2)" = 1 ] || { echo "$output"; false; }
  [[ "$output" == *"C2 unchanged since its pass"* ]]
}

@test "a check that last failed is rerun even when the files it read match an earlier pass" {
  "$VBW" fix done F1 > /dev/null
  printf 'broken\n' > src/pay.txt && git commit -q -am "fix: break"
  vbw_run fix done F2
  [ "$status" -eq 1 ]
  [[ "$output" == *"F2 broke finished work"*"C1 fail"* ]]
  [ "$(runs C1)" = 2 ]
  printf 'paid\n' > src/pay.txt && git commit -q -am "fix: restore"
  vbw_run fix done F2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 3 ]
  [[ "$output" != *"C1 unchanged"* ]]
}

@test "a check that never ran is run, and a check that declares no files is judged by what it read" {
  [ "$(runs C1)" = 0 ]
  "$VBW" fix done F1 > /dev/null
  [ "$(runs C1)" = 1 ] && [ "$(runs C3)" = 1 ]
  printf 'ui more\n' >> src/ui.txt && git commit -q -am "feat: ui"
  vbw_run fix done F2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C3)" = 2 ] || { echo "$output"; false; }
  [[ "$output" != *"C3 unchanged"* ]]
  [ "$(runs C1)" = 1 ]
  [[ "$output" == *"C1 unchanged since its pass"* ]]
}

@test "checks run on the committed code: an uncommitted change outside the fix's files neither fails them nor stops their reuse" {
  printf 'broken\n' > src/receipt.txt
  vbw_run fix done F3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C2)" = 1 ]
  [[ "$output" == *"F3 closed"* ]]
  git checkout -q src/receipt.txt
  edit_record '.fixes += [{id: "F4", req: "R1", attempts: 0, status: "open", note: "d"}]'
  vbw_run fix done F4
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C2)" = 1 ]
  [[ "$output" == *"C2 unchanged since its pass"* ]]
}

@test "uncommitted changes in the fix's files still block closing, and nothing reruns" {
  "$VBW" fix done F1 > /dev/null
  printf 'dirty\n' >> src/receipt.txt
  vbw_run fix done F2
  [ "$status" -eq 1 ]
  [[ "$output" == *"F2 has uncommitted changes in: src/receipt.txt"* ]]
  [ "$(runs C1)" = 1 ]
}

@test "vbw prove and vbw fix done share the store and the rule: each reuses the other's passes" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ]
  jq -e 'has("passes") or has("runs") | not' .vbw/record.json
  # A passing proof closes the open fixes; a fix found afterwards reuses its passes.
  edit_record '.fixes += [{id: "F4", req: "R2", attempts: 0, status: "open", note: "d"}]'
  vbw_run fix done F4
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ] || { echo "C1 $(runs C1) C2 $(runs C2) C3 $(runs C3)"; echo "$output"; false; }
  [[ "$output" == *"C1 unchanged since its pass"* ]]
  [[ "$output" == *"C3 unchanged since its pass"* ]]
  # Only the record changed since the passing proof: nothing it read changed.
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ] || { echo "C1 $(runs C1) C2 $(runs C2) C3 $(runs C3)"; echo "$output"; false; }
  # A pass a fix recorded is reused by the next proof.
  printf 'more\n' >> src/pay.txt && git commit -q -am "fix: pay"
  edit_record '.fixes += [{id: "F5", req: "R1", attempts: 0, status: "open", note: "e"}]'
  vbw_run fix done F5
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 2 ]
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 2 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ] || { echo "C1 $(runs C1) C2 $(runs C2) C3 $(runs C3)"; echo "$output"; false; }
}

@test "vbw prove still fails on a failing check whatever was recorded" {
  "$VBW" fix done F1 > /dev/null
  printf 'broken\n' > src/pay.txt && git commit -q -am "fix: break"
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 fail"* ]]
  [ "$(runs C1)" = 2 ]
}

@test "closing outcomes are the same when a check is skipped: fixed for code, closed for a human requirement" {
  "$VBW" fix done F1 > /dev/null
  vbw_run fix done F3
  [ "$status" -eq 0 ]
  [[ "$output" == *"F3 closed: its requirement goes back to the user for acceptance"* ]]
  [ "$(runs C1)" = 1 ]
  jq -e '(.fixes[] | select(.id == "F3")).status == "closed" and (.requirements[] | select(.id == "R3")).status == "open"' .vbw/record.json
  jq -e '(.fixes[] | select(.id == "F1")).status == "fixed"' .vbw/record.json
}

@test "a missing or damaged store of recorded runs only means the checks run again" {
  "$VBW" fix done F1 > /dev/null
  printf 'not json' > "$(store)"
  vbw_run fix done F2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 2 ]
  [[ "$output" != *"C1 unchanged"* ]]
  in_store src/pay.txt || { cat "$(store)"; false; }
  rm "$(store)"
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "the record never holds passes or read lists, so VBW 2.0.16 still reads it, and closing a fix leaves no record change to commit" {
  vbw_run prove
  [ "$status" -eq 0 ]
  jq -e 'has("passes") or has("runs") | not' .vbw/record.json
  jq -e '[.evidence | .. | strings] | index("src/ui.txt") | not' .vbw/record.json
  in_store src/ui.txt || { cat "$(store)"; false; }
  edit_record '.fixes += [{id: "F4", req: "R2", attempts: 0, status: "open", note: "d"}]'
  before=$(jq -S 'del(.fixes)' .vbw/record.json)
  vbw_run fix done F4
  [ "$status" -eq 0 ]
  [ "$(jq -S 'del(.fixes)' .vbw/record.json)" = "$before" ]
}

@test "a pass of a check the contract no longer has is never used, and the record stays readable" {
  vbw_run prove
  [ "$status" -eq 0 ]
  printf '%s' "$PLAN" | jq '.checks |= map(select(.id != "C1"))' | "$VBW" apply > /dev/null
  vbw_run status
  [ "$status" -eq 0 ]
  jq -e 'has("passes") | not' .vbw/record.json
}
