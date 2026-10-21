#!/usr/bin/env bats
# T174 (docs/workflows.md, docs/proof.md): rule breaks run side by side. vbw
# mutate PLAN Rn.k --queue WHAT FILE... sets one break aside and puts the files
# back at once, running nothing; vbw mutate PLAN --run runs every queued break of
# the plan: each rule's check once on the unbroken code (as the single form, never
# once per break), then the breaks, each in its own proof copy, as many at a time
# as check_jobs allows, and records each result as the single form would. A
# survivor makes it exit 1; a break queued at another commit is dropped and named
# (break it again), and it exits 1 too. Check files that differ from the last
# commit stop it. --queue is for a rule break only; --run with nothing queued
# says how to queue. vbw plan done names queued breaks not run yet. L1: the
# kernel on a fixture project.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  LOG="$TEST_ROOT/runs"
  BAR="$TEST_ROOT/bar"
  mkdir -p "$BAR"
  # Every run logs a line. With $BAR/on, a run on broken code waits (up to 10 s) until
  # a second one is under way, and says whether it saw it: the breaks ran side by side.
  cat > tests/pay.sh <<EOF
out=\$(sh src/pay.sh)
echo run >> "$LOG"
if [ "\$out" != paid ] && [ -f "$BAR/on" ]; then
  touch "$BAR/\$\$"; i=0
  while [ "\$(ls "$BAR" | grep -c '^[0-9]')" -lt 2 ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i + 1)); done
  [ "\$(ls "$BAR" | grep -c '^[0-9]')" -lt 2 ] || touch "$BAR/met.\$\$"
fi
[ "\$out" = paid ]
EOF
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "nothing but paid is printed", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 2 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
}

teardown() { vbw_teardown; }

breaks() { jq -c '[.plans[0].mutations[]? | {t: (.rule.text // "task\(.task)"), r: .result, c: .checks}]' .vbw/record.json; }
queue() {
  local target=$1 what=$2 body=$3
  printf '%s\n' "$body" > src/pay.sh
  run "$VBW" mutate P1.1 "$target" --queue "$what" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat src/pay.sh)" = "$(git show HEAD:src/pay.sh)" ] || { echo "src/pay.sh was not put back: $(cat src/pay.sh)"; return 1; }
}

@test "T174: --queue sets the break aside and puts the file back at once; nothing runs and nothing is recorded" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  [[ "$output" == *"R1.1 queued"* && "$output" == *"vbw mutate P1.1 --run"* ]] || { echo "$output"; false; }
  [ ! -f "$LOG" ] || { echo "a check ran: $(cat "$LOG")"; false; }
  [ "$(breaks)" = '[]' ] || breaks
  git diff --quiet -- src tests || { git status --short; false; }
}

@test "T174: --run runs the queued breaks side by side, the check once unbroken, and records each as red" {
  touch "$BAR/on"
  queue R1.1 "prints unpaid" 'echo unpaid'
  queue R1.2 "prints more than paid" 'echo paid; echo more'
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 red: prints unpaid"* && "$output" == *"R1.2 red: prints more than paid"* ]] || { echo "$output"; false; }
  breaks | jq -e '. == [{t: "paying prints paid", r: "red", c: {C1: "red"}}, {t: "nothing but paid is printed", r: "red", c: {C1: "red"}}]' || breaks
  # One unbroken run of C1 and one run per break; both breaks were under way together.
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 3 ] || { cat "$LOG"; false; }
  [ "$(ls "$BAR" | grep -c '^met\.')" -eq 2 ] || { ls "$BAR"; false; }
  [ -z "$(ls -A .vbw/runtime/mutate-queue/P1.1 2> /dev/null)" ] || ls -R .vbw/runtime/mutate-queue
  git diff --quiet -- src tests || { git status --short; false; }
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "T174: a survivor among the queued breaks is recorded and makes --run exit 1; the others are recorded red" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  queue R1.2 "prints oops on stderr" 'echo paid; echo oops >&2'
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 red"* && "$output" == *"survivor: R1.2"* ]] || { echo "$output"; false; }
  breaks | jq -e 'map(.r) == ["red", "survivor"]' || breaks
}

@test "T174: a break queued at another commit is dropped and named, and --run exits 1" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  printf 'echo paid\n# one more line\n' > src/pay.sh
  "$VBW" commit P1.1 "feat(pay): note" > /dev/null
  queue R1.2 "prints unpaid again" 'echo unpaid'
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1"*"another commit"*"break it again"* && "$output" == *"R1.2 red"* ]] || { echo "$output"; false; }
  breaks | jq -e 'map(.t) == ["nothing but paid is printed"]' || breaks
}

@test "T174: check files that differ from the last commit stop --run, and nothing is recorded" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  printf '\n# stronger\n' >> tests/pay.sh
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"tests/pay.sh"* && "$output" == *"commit them first"* ]] || { echo "$output"; false; }
  [ "$(breaks)" = '[]' ] || breaks
}

@test "T174: --queue is for a rule break; --run with nothing queued says how to queue" {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --queue "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"--queue is for a rule break"* ]] || { echo "$output"; false; }
  run "$VBW" mutate P1.1 R1.1 --queue --none "a reason" < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"--queue is for a rule break"* ]] || { echo "$output"; false; }
  git checkout -q -- src/pay.sh
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"no break waits for P1.1"* && "$output" == *"--queue"* ]] || { echo "$output"; false; }
}

@test "T174: vbw plan done names queued breaks that have not run yet" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"R1.1"* && "$output" == *"vbw mutate P1.1 --run"* ]] || { echo "$output"; false; }
}
