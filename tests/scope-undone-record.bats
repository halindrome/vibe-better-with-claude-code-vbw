#!/usr/bin/env bats
# R204 (docs/record.md, evidence; docs/proof.md, scope): the evidence carries
# evidence.undone, an array of {commit, plan, by} naming each commit the scope
# check left unjudged and the commit that undid it. The record validator
# accepts the field and refuses an entry missing commit, plan or by, with an id
# that is not 40 hex digits, or with a plan id of a wrong shape; a record
# written before the field still reads. vbw show evidence prints one line per
# entry, `scope: <12 hex> (<plan>) undone by <12 hex>, not judged`, and nothing
# for a record without the field. L1: the validator on the documented record,
# and the kernel on a fixture project.

load helper

KEEP_PROTECTED='if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end'

setup() {
  vbw_setup
  VALIDATOR="$PLUGIN_ROOT/lib/record.jq"
  VALID="$TEST_ROOT/valid.json"
  cat > "$VALID" <<'EOF'
{
  "schema": 1,
  "project": { "name": "Shop" },
  "milestone": { "id": "M1", "title": "Checkout", "status": "active" },
  "shipped": [],
  "requirements": [
    { "id": "R1", "text": "Pay by card", "proof": "auto", "status": "failing", "milestone": "M1" }
  ],
  "checks": [ { "id": "C1", "req": "R1", "run": ["npm", "test"], "files": ["tests/pay.test.ts"], "exit": 0, "output": "passed", "timeout": 60 } ],
  "phases": [ { "id": "P1", "title": "Payments", "reqs": ["R1"], "milestone": "M1" } ],
  "plans": [
    { "id": "P1.1", "phase": "P1", "title": "Card form", "reqs": ["R1"], "files": ["src/pay.ts"], "after": [], "status": "done" }
  ],
  "fixes": [],
  "todos": [],
  "decisions": [],
  "commands": { "test": ["npm", "test"] },
  "settings": { "profile": "balanced", "autonomy_cap": 25 },
  "evidence": {
    "at": "2026-10-01T09:00:00Z",
    "contract": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "tree": "cccccccccccccccccccccccccccccccccccccccc",
    "passed": true,
    "checks": { "C1": { "status": "pass", "exit": 0, "seconds": 2, "tail": "" } },
    "commands": { "test": { "status": "skipped", "exit": null, "seconds": 0, "tail": "not approved" } },
    "scope": []
  },
  "lease": null
}
EOF
}

teardown() { vbw_teardown; }

# violations_after JQ: the violations of the documented record after the edit; [] means valid.
violations_after() {
  jq "$1" "$VALID" | jq -c -f "$VALIDATOR"
}

A40='1111111111111111111111111111111111111111'
B40='2222222222222222222222222222222222222222'

@test "R204: the validator accepts evidence without undone, with an empty undone and with well-formed entries" {
  run violations_after '.'
  [ "$output" = "[]" ] || { echo "$output"; false; }
  run violations_after '.evidence.undone = []'
  [ "$output" = "[]" ] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [{commit: \"$A40\", plan: \"P1.1\", by: \"$B40\"}, {commit: \"$B40\", plan: \"P12.34\", by: \"$A40\"}]"
  [ "$output" = "[]" ] || { echo "$output"; false; }
}

@test "R204: the validator refuses an entry missing commit, plan or by" {
  run violations_after ".evidence.undone = [{plan: \"P1.1\", by: \"$B40\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [{commit: \"$A40\", by: \"$B40\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [{commit: \"$A40\", plan: \"P1.1\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
}

@test "R204: the validator refuses an id that is not 40 hex digits, a plan id of a wrong shape, an extra field and a non-array" {
  run violations_after ".evidence.undone = [{commit: \"${A40:0:12}\", plan: \"P1.1\", by: \"$B40\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [{commit: \"$A40\", plan: \"P1.1\", by: \"${B40:0:39}g\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [{commit: \"$A40\", plan: \"P1\", by: \"$B40\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [{commit: \"$A40\", plan: \"card form\", by: \"$B40\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [{commit: \"$A40\", plan: \"P1.1\", by: \"$B40\", why: \"x\"}]"
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
  run violations_after '.evidence.undone = "none"'
  [[ "$output" == *"evidence.undone"* ]] || { echo "$output"; false; }
}

@test "R204: the validator keeps the meaning of passed and scope beside undone" {
  run violations_after ".evidence.undone = [{commit: \"$A40\", plan: \"P1.1\", by: \"$B40\"}] | .evidence.scope = [\"x (P1.1) changed y, which is not in the plan\"] | .evidence.passed = false"
  [ "$output" = "[]" ] || { echo "$output"; false; }
  run violations_after ".evidence.undone = [] | .evidence.scope = \"none\""
  [[ "$output" == *"evidence needs at, contract, tree, passed"* ]] || { echo "$output"; false; }
}

# --- vbw show evidence -------------------------------------------------------

# proved_project: a project with one proof recorded, so show evidence has evidence to render.
proved_project() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:.milestone.id}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
}

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/edit.json" > .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

@test "R204: vbw show evidence prints one line per undone entry, in the proof summary's words, after the scope lines" {
  proved_project
  edit_record ".evidence.undone = [{commit: \"$A40\", plan: \"P1.1\", by: \"$B40\"}, {commit: \"$B40\", plan: \"P1.1\", by: \"$A40\"}]
    | .evidence.scope = [\"${B40:0:12} (P1.1) changed src/x.txt, which is not in the plan\"]"
  vbw_run show evidence
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF "  scope: ${A40:0:12} (P1.1) undone by ${B40:0:12}, not judged" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF "  scope: ${B40:0:12} (P1.1) undone by ${A40:0:12}, not judged" || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'undone by')" -eq 2 ] || { echo "$output"; false; }
  local v u
  v=$(printf '%s\n' "$output" | grep -nF 'changed src/x.txt' | head -n 1 | cut -d: -f1)
  u=$(printf '%s\n' "$output" | grep -nF 'undone by' | head -n 1 | cut -d: -f1)
  [ -n "$v" ] && [ -n "$u" ] && [ "$u" -gt "$v" ] || { echo "violation at line ${v:-none}, undone at line ${u:-none}"; echo "$output"; false; }
}

@test "R204: a record written before the field reads, and vbw show evidence prints nothing for it" {
  proved_project
  edit_record 'del(.evidence.undone)'
  jq -e '.evidence | has("undone") | not' .vbw/record.json
  vbw_run show evidence
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"passed"* ]] || { echo "$output"; false; }
  [[ "$output" != *"undone"* ]] || { echo "$output"; false; }
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
