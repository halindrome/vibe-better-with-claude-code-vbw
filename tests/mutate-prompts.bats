#!/usr/bin/env bats
# R188 (P140; D379, D380, D381; docs/workflows.md): the builders run the
# mutation check during the build. The building workflow passes each plan's
# rigor tier to its builder; a plan of a standard or deep phase gets the
# mutation instruction, a plan of an express phase none. The Dev's
# instructions add the mutation step after the green step: at standard one
# small break of the plan's own code per rule, at deep also per task and per
# error and edge case its rules state, each followed by vbw mutate and undoing
# the break; skipped at express; never in a fix. A survivor is strengthened in
# the approved check file of its own requirement, in place, never another
# requirement's, never weakened, the same break re-run until red, committed
# with the plan, and the notes say it waits for one approval. Two strengthening
# attempts that stay green end in vbw plan block naming the rule, and the phase
# rises one tier as with any Dev block. The Docs agent does the same for the
# rules its documents deliver. Budgets hold: workflows 1,500 lines, each agent
# 900 words. L1, with stubbed agents (tests/helpers/run-workflow.js) and the
# kernel on a fixture project: no model runs.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows"
DEV="$PLUGIN_ROOT/agents/dev.md"
DOCS="$PLUGIN_ROOT/agents/docs.md"

teardown() { vbw_teardown; }

needs_node() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# build_prompts: the building workflow's agent calls for four plans, one per
# tier and a documentation plan at standard, as JSON {label: prompt}.
build_prompts() {
  node "$RUN" "$WF/building.js" '{"plans":["P1.1","P2.1","P3.1","P4.1"],"docs":["P4.1"],
    "rigor":{"P1":{"tier":"standard"},"P2":{"tier":"deep"},"P3":{"tier":"express"},"P4":{"tier":"standard"}}}' '{}' \
    | jq -c '[.calls[] | {key: .opts.label, value: .prompt}] | from_entries'
}
prompt_of() { build_prompts | jq -r --arg l "$1" '.[$l]'; }
# has_line FILE WORD...: one line of FILE holds every WORD (case-insensitive).
has_line() {
  local f=$1 w lines
  shift
  lines=$(cat "$f")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of ${f##*/} holds all of: $*"; return 1; }; done
}

@test "R188: building passes each plan's tier; standard and deep plans get the mutation instruction, express none" {
  needs_node
  local p
  p=$(prompt_of "dev P1.1")
  printf '%s' "$p" | grep -Eiq 'tier[^a-z]*standard' && printf '%s' "$p" | grep -qi mutation || { echo "$p"; false; }
  p=$(prompt_of "dev P2.1")
  printf '%s' "$p" | grep -Eiq 'tier[^a-z]*deep' && printf '%s' "$p" | grep -qi mutation || { echo "$p"; false; }
  p=$(prompt_of "dev P3.1")
  ! printf '%s' "$p" | grep -qi mutat || { echo "$p"; false; }
  p=$(prompt_of "docs P4.1")
  printf '%s' "$p" | grep -Eiq 'tier[^a-z]*standard' && printf '%s' "$p" | grep -qi mutation || { echo "$p"; false; }
}

@test "R188: the fixing workflow gives no mutation instruction" {
  needs_node
  ! grep -qi mutat "$WF/fixing.js" || { grep -ni mutat "$WF/fixing.js"; false; }
  node "$RUN" "$WF/fixing.js" '{"groups":[["F1"]],"rigor":{"P1":{"tier":"deep"}}}' '{}' \
    | jq -e '[.calls[].prompt | test("mutat"; "i")] | any | not' > /dev/null
}

@test "R188: the Dev's mutation step comes after green, breaks the plan's own code once per rule at standard, runs vbw mutate, undoes the break, and is skipped at express" {
  grep -q 'vbw mutate' "$DEV" || { echo "dev.md does not name vbw mutate"; false; }
  has_line "$DEV" mutation green
  has_line "$DEV" "each rule" standard
  has_line "$DEV" "vbw mutate" undo
  has_line "$DEV" mutation express
  has_line "$DEV" break "own"
}

@test "R188: at deep the Dev also breaks each task and each error and edge case its rules state" {
  has_line "$DEV" deep task error edge
}

@test "R188: a survivor is strengthened in place in its own requirement's check file, never another's, never weakened, re-run until red, committed with the plan, and waits for one approval" {
  has_line "$DEV" survivor strengthen "in place"
  has_line "$DEV" strengthen "never another requirement"
  has_line "$DEV" strengthen weaken
  has_line "$DEV" "same break" red
  has_line "$DEV" strengthen commit approval
}

@test "R188: two strengthening attempts that stay green end in vbw plan block naming the rule" {
  has_line "$DEV" "vbw plan block" two rule
}

@test "R188: the Dev never runs the mutation step in a fix" {
  has_line "$DEV" mutation fix never
}

@test "R188: the Docs agent breaks the statements its plan delivers the same way at standard and deep" {
  has_line "$DOCS" "vbw mutate" standard deep
}

@test "R188: a Dev block naming the rule raises the phase one tier, as any Dev block does" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests
  printf 'true\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"}]}' | "$VBW" apply > /dev/null
  run "$VBW" plan block P1.1 "R1.1 stays green after two strengthening attempts (checked stdout, then stderr)" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.phases[0].tier == "deep" and (.phases[0].escalations[-1].reason | contains("R1.1"))' .vbw/record.json || { jq '.phases[0]' .vbw/record.json; false; }
}

@test "R188: the workflows stay within 1,500 lines and the Dev and Docs agents within 900 words each" {
  local total=0 f n
  for f in "$WF"/*.js; do
    n=$(grep -cvE '^[[:space:]]*(//|$)' "$f" || true)
    total=$((total + n))
  done
  [ "$total" -le 1500 ] || { echo "workflow lines: $total"; false; }
  [ "$(wc -w < "$DEV")" -le 900 ] || { echo "dev.md: $(wc -w < "$DEV") words"; false; }
  [ "$(wc -w < "$DOCS")" -le 900 ] || { echo "docs.md: $(wc -w < "$DOCS") words"; false; }
}
