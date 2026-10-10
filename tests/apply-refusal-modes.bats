#!/usr/bin/env bats
# R156 (docs/workflows.md): every refusal of vbw apply names, in its text, the
# mode it came from: "full apply" (vbw apply with neither --add nor --patch),
# "--add" or "--patch". At least one refusal per mode is covered, among them
# input that is not valid JSON, an unknown field, an invalid tier, an open run,
# a changed started plan, a missing rule and a tier below its floor. An unknown
# option prints the usage line listing the three modes and exits 2. L1.

load helper
load replan-helper

setup() {
  vbw_setup
  replan_project
  # P1.1 has started. Checks and rules make the rule refusals reachable.
  printf 'true\n' > tests/c1.sh
  printf 'true\n' > tests/c2.sh
  printf 'true\n' > tests/c3.sh
  replan_accepted full "$(replan_doc '.checks = [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
      {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}]
    | .rules = [{req: "R1", text: "paying works", check: "C1"}, {req: "R2", text: "a receipt is shown", check: "C2"}]')"
  FULL=$(jq -c '.milestone.id as $m | {phases: [.phases[] | select(.milestone == $m) | {id, title, reqs, goal, criteria, tier}],
      plans: [.plans[] | {id, phase, title, reqs, files, after, tasks}], checks: .checks,
      rules: [.requirements[] | .id as $q | (.rules // [])[] | {req: $q, text, check}]}' .vbw/record.json)
  ADD='{"phases": [{"id": "P3", "title": "Refund", "reqs": ["R3"], "goal": "Customers get refunds", "criteria": ["a refund is paid"], "tier": "standard"}],
    "plans": [{"id": "P3.1", "phase": "P3", "title": "Refund", "reqs": ["R3"], "files": ["src/r.txt"], "after": []}],
    "checks": [{"id": "C3", "req": "R3", "run": ["sh", "tests/c3.sh"], "files": ["tests/c3.sh"]}],
    "rules": [{"req": "R3", "text": "a refund is paid", "check": "C3"}]}'
  replan_start P1.1
}

teardown() { vbw_teardown; }

# refused_as MODE LABEL DOC: vbw apply in MODE refuses DOC, writes nothing, and
# its message names LABEL.
refused_as() {
  replan_refused "$1" "$3" || return 1
  [[ "$output" == *"$2"* ]] || { echo "the $1 refusal does not name '$2': $output"; return 1; }
}

full_with() { printf '%s' "$FULL" | jq -c "$1"; }
add_with() { printf '%s' "$ADD" | jq -c "$1"; }

@test "R156: full apply refusals name the full apply: not JSON, an unknown field, an invalid tier" {
  refused_as full "full apply" 'not json {'
  refused_as full "full apply" "$(full_with '.plans[0].file = "x"')"
  refused_as full "full apply" "$(full_with '.phases[0].tier = "fast"')"
}

@test "R156: full apply refusals name the full apply: an open run, a changed started plan, a missing rule, a tier below its floor" {
  refused_as full "full apply" "$(full_with '(.plans[] | select(.id == "P1.1")).files += ["src/extra.txt"]')"
  refused_as full "full apply" "$(full_with '.phases += [{id: "P3", title: "Refund", reqs: ["R3"], goal: "g", criteria: ["c"], tier: "standard"}]
    | .plans += [{id: "P3.1", phase: "P3", title: "Refund", reqs: ["R3"], files: ["src/r.txt"], after: []}]
    | .checks += [{id: "C3", req: "R3", run: ["sh", "tests/c3.sh"], files: ["tests/c3.sh"]}]')"
  refused_as full "full apply" "$(full_with '(.plans[] | select(.id == "P2.1")).files = ["src/payments/charge.js"]')"
  "$VBW" run start build P2.1 > /dev/null
  refused_as full "full apply" "$FULL"
}

@test "R156: --add refusals name --add: not JSON, an unknown field, an invalid tier, a phase id in use" {
  refused_as add "--add" 'not json {'
  refused_as add "--add" "$(add_with '.phases[0].colour = "red"')"
  refused_as add "--add" "$(add_with '.phases[0].tier = "fast"')"
  refused_as add "--add" "$(add_with '.phases[0].id = "P2" | .plans[0].phase = "P2"')"
}

@test "R156: --add refusals name --add: a missing rule, a tier below its floor, an open run" {
  refused_as add "--add" "$(add_with '.rules = []')"
  refused_as add "--add" "$(add_with '.plans[0].files = ["src/payments/refund.js"]')"
  "$VBW" run start build P2.1 > /dev/null
  refused_as add "--add" "$ADD"
}

@test "R156: --patch refusals name --patch: not JSON, phases, an unknown field, a changed started plan, a rule naming no check, an open run" {
  refused_as patch "--patch" 'not json {'
  refused_as patch "--patch" '{"phases": []}'
  refused_as patch "--patch" '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt page", "reqs": ["R2"], "files": ["src/c.txt"], "after": [], "colour": "red"}]}'
  refused_as patch "--patch" '{"plans": [{"id": "P1.1", "phase": "P1", "title": "Pay form", "reqs": ["R1"], "files": ["src/a.txt", "src/z.txt"], "after": []}]}'
  refused_as patch "--patch" '{"rules": [{"req": "R1", "text": "a second rule", "check": "C9"}]}'
  "$VBW" run start build P2.1 > /dev/null
  refused_as patch "--patch" '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt", "reqs": ["R2"], "files": ["src/c.txt"], "after": []}]}'
}

@test "R156: an unknown option prints the usage line listing the three modes and exits 2" {
  local out code=0 before
  before=$(cksum < .vbw/record.json)
  out=$(printf '%s' "$FULL" | "$VBW" apply --foo 2>&1) || code=$?
  [ "$code" -eq 2 ] || { echo "exit $code: $out"; false; }
  [[ "$out" == *"usage: vbw apply"* ]] || { echo "$out"; false; }
  [[ "$out" == *"full"* && "$out" == *"--add"* && "$out" == *"--patch"* ]] || { echo "$out"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}
