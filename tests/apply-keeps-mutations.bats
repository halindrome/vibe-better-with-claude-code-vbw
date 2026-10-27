#!/usr/bin/env bats
# T154 (D399): the breaks a mutation check recorded for a plan are the kernel's
# evidence, like its status: vbw apply (full or --patch) never drops them. On
# 2026-10-14 a patch that added a file to a reset plan erased its 19 recorded
# breaks, the survivors among them, and the next proof flagged the check file
# they had opened as out of scope. L1.

load helper
load fixture-helper

kept_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  doc > "$TEST_ROOT/doc.json"
  "$VBW" apply < "$TEST_ROOT/doc.json" > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  printf 'echo nope\n' > src/pay.sh
  VBW_SESSION_ID=s1 "$VBW" mutate P1.1 R1.1 "prints nope" src/pay.sh > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  jq -e '[.plans[] | select(.id == "P1.1") | .mutations[]] | length == 1' .vbw/record.json
}

setup_file() { fixture_build kept kept_project; }
setup() { fixture_copy kept; }

teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# doc [FILE...]: the plan document; extra files join the plan's files.
doc() {
  jq -nc --args '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: (["src/pay.sh"] + $ARGS.positional), after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"}]}' "$@"
}

kept() { jq -e '[.plans[] | select(.id == "P1.1") | .mutations[] | select(.result == "red" and .what == "prints nope")] | length == 1' .vbw/record.json || { jq '.plans' .vbw/record.json; return 1; }; }

@test "T154: a patch that adds a file to a reset plan keeps its recorded breaks" {
  "$VBW" plan reset P1.1 > /dev/null
  doc src/log.sh | jq -c '{plans, checks}' | "$VBW" apply --patch > /dev/null
  jq -e '.plans[] | select(.id == "P1.1") | .files | index("src/log.sh")' .vbw/record.json
  kept
}

@test "T154: a full apply that keeps the plan keeps its recorded breaks" {
  "$VBW" plan reset P1.1 > /dev/null
  doc src/log.sh | "$VBW" apply > /dev/null
  kept
}

# R213 (T190): a started plan's note (its blocked reason) is kernel evidence like its
# status and breaks: no mode of vbw apply drops it; vbw show plan and vbw show roadmap
# print it after the apply as before.
note_kept() {
  jq -e '.plans[] | select(.id == "P1.1") | .status == "blocked" and .note == "waits for the receipt API"' .vbw/record.json \
    || { echo "after $1:"; jq '.plans' .vbw/record.json; return 1; }
  "$VBW" show plan P1.1 | grep -qF '[blocked]: waits for the receipt API' || { echo "after $1, vbw show plan lost the reason:"; "$VBW" show plan P1.1; return 1; }
  "$VBW" show roadmap | grep -qF 'waits for the receipt API' || { echo "after $1, vbw show roadmap lost the reason:"; "$VBW" show roadmap; return 1; }
}

@test "R213: a full apply, a patch and an --add keep a blocked plan's note with its status and breaks; vbw show plan and vbw show roadmap print the reason" {
  "$VBW" plan block P1.1 "waits for the receipt API" > /dev/null
  note_kept "the block"
  doc | "$VBW" apply > /dev/null
  note_kept "a full apply"
  doc | jq -c '{plans, checks}' | "$VBW" apply --patch > /dev/null
  note_kept "a patch"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P2", title: "Receipt", reqs: ["R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: []}],
    checks: [{id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}],
    rules: [{req: "R2", text: "a receipt is printed", check: "C2"}]}' | "$VBW" apply --add > /dev/null
  note_kept "an --add"
  kept
}

@test "R213: a plan without a note gains none from an apply; the note goes only with a status change (vbw plan reset)" {
  doc | "$VBW" apply > /dev/null
  jq -e '.plans[] | select(.id == "P1.1") | has("note") | not' .vbw/record.json || { jq '.plans' .vbw/record.json; false; }
  "$VBW" plan block P1.1 "waits for the receipt API" > /dev/null
  "$VBW" plan reset P1.1 > /dev/null
  jq -e '.plans[] | select(.id == "P1.1") | .status == "planned" and (has("note") | not)' .vbw/record.json || { jq '.plans' .vbw/record.json; false; }
}
