#!/usr/bin/env bats
# R207 (docs/workflows.md): vbw mutate PLAN Rn.k WHAT FILE..., vbw mutate PLAN
# taskK ... WHAT FILE... and vbw mutate PLAN --run end with where their time went,
# in the proof's form, measured by prooftime.sh's clock and nothing estimated:
#   VBW's own work: X of Y min
#     steps of W s: copies A, unbroken B, break R3.1 C, waits D, saving E
# copies: making, breaking, restoring and removing the clean copies; unbroken:
# the checks on the unbroken code; one entry per break named by its target
# ("break R3.1", "break task2"; in --run a wave of breaks run side by side is one
# entry naming its targets, "breaks R3.1 R3.2"); waits: the seconds spent waiting
# for a computer-wide slot (the figure the slots count); saving: recording the
# result. Seconds carry one decimal and the steps sum to W within rounding; X is
# the own work (copies, saving and the read tracking inside the runs). The two
# lines come after the result lines (red, survivor, "caught by the pending one")
# and before the slots line, for every outcome; the verdict, the recorded entry,
# the strengthened and pending markings and the exit code are what they were
# without them. A refusal prints no breakdown; --queue and --none print none.
# L1: the kernel on a fixture project; the wait case holds the only slot from
# another project (tests/machine-helper.bash).

load helper
load machine-helper
load fixture-helper

# shop_here: the shop in the current project folder: two requirements, two plans,
# C1 checks what pay.sh prints, C3 that it prints one line, C2 cannot fail on what
# receipt.sh prints. Approved and committed.
shop_here() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo receipt\n' > src/receipt.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  printf '[ "$(sh src/pay.sh | wc -l | tr -d " ")" = 1 ]\n' > tests/pay-once.sh
  printf 'sh src/receipt.sh > /dev/null\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay", "print once"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/pay-once.sh"], files: ["tests/pay-once.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "paying prints one line", check: "C3"},
            {req: "R2", text: "a receipt is printed", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

built_project() {
  vbw_setup
  shop_here
}

# pair: on 2 cores (limit 1), the shop and, beside it, project B whose one unit
# works 5 s, to hold the only slot. For fixture_build.
pair() {
  machine_setup
  cores 2
  shop_here
  machine_project "$OTHER" B 1 5
}

setup_file() {
  fixture_build built built_project
  fixture_build pair pair
}
setup() { fixture_copy built; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

OWN_RE="^VBW's own work: [0-9]+\.[0-9] of [0-9]+\.[0-9] min$"
STEPS_RE='^  steps of [0-9]+\.[0-9] s: copies [0-9]+\.[0-9], unbroken [0-9]+\.[0-9], (breaks? [^,]+ [0-9]+\.[0-9], )+waits [0-9]+\.[0-9], saving [0-9]+\.[0-9]$'

# split: OWN (the own-work line), STEPS (the line after it), BEFORE (every line
# before OWN) and AFTER (every line after STEPS), from $output. Fails when the
# own-work line is missing or appears twice.
split() {
  local n
  [ "$(printf '%s\n' "$output" | grep -cE "$OWN_RE")" -eq 1 ] || { echo "own-work line count is not 1:"; echo "$output"; return 1; }
  n=$(printf '%s\n' "$output" | grep -nE "$OWN_RE" | cut -d: -f1)
  OWN=$(printf '%s\n' "$output" | sed -n "${n}p")
  STEPS=$(printf '%s\n' "$output" | sed -n "$((n + 1))p")
  BEFORE=$(printf '%s\n' "$output" | sed -n "1,$((n - 1))p")
  AFTER=$(printf '%s\n' "$output" | sed -n "$((n + 2)),\$p")
  [[ "$STEPS" =~ $STEPS_RE ]] || { echo "no steps line after the own-work line: $STEPS"; echo "$output"; return 1; }
}

# none: the output carries no breakdown.
none() {
  if printf '%s\n' "$output" | grep -qE "$OWN_RE|^  steps of "; then echo "a breakdown was printed:"; echo "$output"; return 1; fi
}

# step NAME: the seconds of step NAME in $STEPS (empty when absent).
step() { printf '%s\n' "$STEPS" | sed 's/^  steps of [0-9.]* s: //' | tr ',' '\n' | sed 's/^ //' | awk -v n="$1" '{v=$NF; $NF=""; sub(/ $/, ""); if ($0 == n) print v}'; }
# names: the step names of $STEPS, in order, one per line.
names() { printf '%s\n' "$STEPS" | sed 's/^  steps of [0-9.]* s: //' | tr ',' '\n' | sed 's/^ //' | awk '{$NF=""; sub(/ $/, ""); print}'; }
# total: W of $STEPS.
total() { printf '%s\n' "$STEPS" | sed 's/^  steps of \([0-9.]*\) s:.*/\1/'; }
# sum_ok: the steps sum to W within rounding (a tenth per figure).
sum_ok() {
  local w s k
  w=$(total)
  s=$(printf '%s\n' "$STEPS" | sed 's/^  steps of [0-9.]* s: //' | tr ',' '\n' | awk '{s += $NF} END {printf "%.1f", s}')
  k=$(names | wc -l | tr -d ' ')
  awk -v w="$w" -v s="$s" -v k="$k" 'BEGIN {d = w - s; if (d < 0) d = -d; exit !(d <= 0.1 * k + 0.05)}' \
    || { echo "steps sum $s, wall $w: $STEPS"; return 1; }
}

last_break() { jq -c --arg p "$1" '[.plans[] | select(.id == $p) | .mutations // [] | .[]] | last' .vbw/record.json; }

@test "R207: a red rule break ends with the own-work line and the split: copies, unbroken, break Rn.k, waits, saving, summing to the wall" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$BEFORE" = "R1.1 red: prints unpaid instead of paid
C1 red" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "lines after the split: $AFTER"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break R1.1|waits|saving|" ] || { names; false; }
  sum_ok
  last_break P1.1 | jq -e '(keys | sort) == ["at","checks","files","head","result","rule","what"] and .result == "red" and .checks == {C1: "red"}' || { last_break P1.1; false; }
  [ "$(cat src/pay.sh)" = "$(git show HEAD:src/pay.sh)" ]
}

@test "R207: a survivor keeps its exit 1 and its line; the breakdown follows it" {
  printf 'echo nothing\n' > src/receipt.sh
  vbw_run mutate P1.2 R2.1 "prints nothing" src/receipt.sh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  split
  [ "$BEFORE" = "survivor: R2.1 (a receipt is printed): C2 still pass" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "$output"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break R2.1|waits|saving|" ] || { names; false; }
  last_break P1.2 | jq -e '.result == "survivor" and (keys | sort) == ["at","checks","files","head","result","rule","what"]' || { last_break P1.2; false; }
}

@test "R207: a task break names its entry by the task" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 task1 "prints unpaid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(printf '%s\n' "$BEFORE" | head -n 1)" = "task1 red: prints unpaid" ] || { echo "$output"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break task1|waits|saving|" ] || { names; false; }
  sum_ok
  last_break P1.1 | jq -e '.task == 1 and .result == "red"' || { last_break P1.1; false; }
}

@test "R207: a break caught by a check file waiting for approval keeps its lines, the pending marking and exit 0; the breakdown comes after them" {
  printf 'echo nothing\n' > src/receipt.sh
  run "$VBW" mutate P1.2 R2.1 "prints nothing" src/receipt.sh < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  printf '[ "$(sh src/receipt.sh)" = receipt ]\n' > tests/receipt.sh
  git commit -q -am "test(receipt): check what is printed"
  printf 'echo nothing\n' > src/receipt.sh
  vbw_run mutate P1.2 R2.1 "prints nothing" src/receipt.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$BEFORE" = "vbw: waiting for approval (new or changed since approved): tests/receipt.sh
R2.1 survives the approved check; caught by the pending one: tests/receipt.sh
C2 red
the pending file still needs the one approval before the proof" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "$output"; false; }
  last_break P1.2 | jq -e '.result == "red" and .pending == ["tests/receipt.sh"]' || { last_break P1.2; false; }
}

@test "R207: the figures are measured: a check that takes a second on broken code puts it into the break's entry" {
  printf 'out=$(sh src/pay.sh)\n[ "$out" = paid ] || sleep 1\n[ "$out" = paid ]\n' > tests/pay.sh
  git commit -q -am "test(pay): slow when red"
  "$VBW" approve > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints unpaid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  awk -v b="$(step 'break R1.1')" -v u="$(step unbroken)" 'BEGIN {exit !(b >= 1.0 && u < b)}' || { echo "$STEPS"; false; }
  sum_ok
}

@test "R207: a refusal ends with its message as today and prints no breakdown: red on the unbroken code, a dirty check file, a stale queued break" {
  printf 'echo unpaid\n' > src/pay.sh
  git commit -q -am "feat(pay): broken on purpose"
  printf 'echo nothing\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints nothing" src/pay.sh
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"checks do not pass on the unbroken code"* ]] || { echo "$output"; false; }
  none
  git checkout -q HEAD~1 -- src/pay.sh && git commit -q -am "fix(pay): paid again"
  printf 'echo paid # touched\n' > src/pay.sh
  printf '# dirty\n' >> tests/pay.sh
  vbw_run mutate P1.1 R1.1 "a comment" src/pay.sh
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"check files differ from the last commit"* ]] || { echo "$output"; false; }
  none
  git checkout -q -- tests/pay.sh src/pay.sh
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh > /dev/null
  printf 'later\n' > src/later.txt
  git add src/later.txt && git commit -q -m "chore: another commit"
  vbw_run mutate P1.1 --run
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"was queued at another commit"* ]] || { echo "$output"; false; }
  none
}

@test "R207: --queue and --none run no break and print no breakdown" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  none
  vbw_run mutate P1.1 task2 --none "documentation only"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  none
  vbw_run mutate P1.2 R2.1 --none "the check judges the record alone"
  none
}

@test "R207: --run one at a time ends with one entry per break in queue order, after the last result" {
  "$VBW" config set check_jobs 1 > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh > /dev/null
  printf 'echo paid\necho paid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.2 --queue "prints twice" src/pay.sh > /dev/null
  vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(printf '%s\n' "$BEFORE" | tail -n 2)" = "R1.2 red: prints twice
C3 red" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "$output"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break R1.1|break R1.2|waits|saving|" ] || { names; false; }
  sum_ok
  jq -e '[.plans[] | select(.id == "P1.1") | .mutations[] | .result] == ["red", "red"]' .vbw/record.json
}

@test "R207: --run with breaks side by side names the wave's targets in one entry" {
  "$VBW" config set check_jobs 2 > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh > /dev/null
  printf 'echo paid\necho paid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.2 --queue "prints twice" src/pay.sh > /dev/null
  vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(names | tr '\n' '|')" = "copies|unbroken|breaks R1.1 R1.2|waits|saving|" ] || { names; false; }
  sum_ok
}

@test "R207: waits is the time the run waited for a computer-wide slot, and the slots line still comes last" {
  fixture_copy pair
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  wait_starts 1 B-
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints unpaid" src/pay.sh
  wait "$BG_PID" || true
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  awk -v w="$(step waits)" 'BEGIN {exit !(w >= 1.0)}' || { echo "$STEPS"; false; }
  sum_ok
  [[ "$AFTER" =~ ^waited\ [0-9]+\ s\ for\ other\ VBW\ runs\ on\ this\ computer ]] || { echo "after the split: $AFTER"; echo "$output"; false; }
  [ "$(printf '%s\n' "$AFTER" | wc -l | tr -d ' ')" -eq 1 ] || { echo "$AFTER"; false; }
}

@test "R207: without a wait the entry reads 0.0 and no slots line follows" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints unpaid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(step waits)" = "0.0" ] || { echo "$STEPS"; false; }
  [ -z "$AFTER" ]
}
