#!/usr/bin/env bats
# R166 (docs/proof.md): QA verdicts and shipping accept a proof that reused
# results under the read-list rule; they no longer demand vbw prove --full, and
# vbw next goes on to QA after such a proof. Closing a fix (vbw fix done) picks
# the checks to run with the same rule as vbw prove: a check of finished work
# runs when a file it read changed, even a file no plan of the fix lists, and a
# check whose reads did not change is reused ("unchanged since its pass").
# Checks log their runs to $RANLOG. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  export RANLOG="$TEST_ROOT/ran.log"
  # C1 reads src/pay.txt and src/rates.txt; no plan lists src/rates.txt.
  printf 'echo C1 >> "$RANLOG"\ngrep -qx paid src/pay.txt\ngrep -q . src/rates.txt\n' > tests/pay.sh
  printf 'echo C2 >> "$RANLOG"\ngrep -qx sent src/receipt.txt\n' > tests/receipt.sh
  printf '1\n' > src/rates.txt
  printf 'unread\n' > src/other.txt
  git add -A && git commit -q -m "chore: tests"
  printf '%s' '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1", "R2"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]},
              {"id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  printf 'sent\n' > src/receipt.txt && "$VBW" commit P1.2 "feat(receipt): receipt" > /dev/null
  "$VBW" plan "done" P1.1 > /dev/null
  "$VBW" plan "done" P1.2 > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$RANLOG"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

# reused_proof: a proof after a commit that changes nothing any check read.
reused_proof() {
  printf 'more\n' >> src/other.txt
  git add src/other.txt && git commit -q -m "chore: other"
  "$VBW" prove > /dev/null || return 1
  jq -e '.evidence.full == false and any(.evidence.checks[]; .reused == true)' .vbw/record.json > /dev/null
}

@test "R166: vbw qa record accepts a proof that reused results under the read-list rule" {
  reused_proof
  vbw_run qa record P1 pass standard "2/2 checks"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"vbw prove --full"* ]] || { echo "$output"; false; }
  jq -e '.phases[0].qa.result == "pass"' .vbw/record.json
}

@test "R166: after a proof that reused results, vbw next goes on to QA and asks for no full proof" {
  reused_proof
  vbw_run next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "qa" and (.detail.full // false) == false' || { echo "$output"; false; }
}

@test "R166: vbw ship accepts a proof that reused results under the read-list rule" {
  vbw_run qa record P1 pass standard "2/2 checks"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  reused_proof
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"vbw prove --full"* ]] || { echo "$output"; false; }
}

@test "R166: vbw fix done runs a finished requirement's check when a file it read changed, though no plan of the fix lists that file" {
  edit_record '.fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "receipt"}]'
  git commit -q -am "chore(vbw): fix F1"
  printf '2\n' >> src/rates.txt
  git add src/rates.txt && git commit -q -m "fix: rates"
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ " $(ran)" == *" C1 "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: vbw fix done reuses a check none of whose read files changed since its pass, and says so" {
  edit_record '.fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "receipt"}]'
  git commit -q -am "chore(vbw): fix F1"
  printf '2\n' >> src/rates.txt
  git add src/rates.txt && git commit -q -m "fix: rates"
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ " $(ran)" != *" C2 "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^C2 unchanged since its pass' || { echo "$output"; false; }
}
