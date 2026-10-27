#!/usr/bin/env bats
# R156 (docs/workflows.md): every refusal of vbw apply names, in its text, the
# mode it came from: "full apply" (vbw apply with neither --add nor --patch),
# "--add" or "--patch". At least one refusal per mode is covered, among them
# input that is not valid JSON, an unknown field, an invalid tier, an open run,
# a changed started plan, a missing rule and a tier below its floor. An unknown
# option prints the usage line listing the three modes and exits 2. L1.

load helper
load replan-helper
load fixture-helper

built_project() {
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

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

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

# R211 and R212 (T187, T191): two refusals that stop a red mutation baseline and an
# undefined rule owner, judged on the record as the document would leave it, in every mode.

# r211_named CHECK A B: the refusal names the check and both plans, says why, and ends with its next step.
r211_named() {
  [[ "$output" == *"$1"* && "$output" == *"$2"* && "$output" == *"$3"* ]] || { echo "does not name $1, $2 and $3: $output"; return 1; }
  [[ "$output" == *"unbroken code"* ]] || { echo "does not say why (red on unbroken code): $output"; return 1; }
  last_line_is "$TWO_OWNER_NEXT"
}
# last_line_is TEXT: the refusal's last line is its next step, word for word (R216).
last_line_is() {
  local last
  last=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)
  [ "$last" = "$1" ] || { echo "the last line is not '$1': $output"; return 1; }
}
TWO_OWNER_NEXT="Next: give each plan's rules a check of their own (a separate test file, or the same file with a case filter as a distinct check), or move the rules to one plan"
MIXED_NEXT='Next: name a plan on every rule of the requirement, or on none (vbw apply --patch rewords a rule: {"rule": "Rn.k", "plan": "P1.1"})'
# beside_named CHECK A B: the refusal says the two plans build beside each other, and ends with the two-owner next step.
beside_named() {
  [[ "$output" == *"$1 is owned by two plans that build beside each other (a shared wave): $2 and $3; the first Dev's mutation step would run $1 before the other Dev committed, a race that fails only sometimes"* ]] || { echo "not the beside words for $1, $2, $3: $output"; return 1; }
  last_line_is "$TWO_OWNER_NEXT"
}
# r2_two_plans AFTER FILES: FULL with P2.2 (after AFTER, files FILES) and C2's rules naming P2.1 and P2.2.
r2_two_plans() {
  full_with ".plans += [{id: \"P2.2\", phase: \"P2\", title: \"Receipt mail\", reqs: [\"R2\"], files: $2, after: $1, tasks: [\"mail\"]}]
    | .rules = [.rules[] | if .req == \"R2\" then . + {plan: \"P2.1\"} else . end] + [{req: \"R2\", text: \"a receipt is mailed\", check: \"C2\", plan: \"P2.2\"}]"
}

@test "R211 R216: full apply refuses a check whose rules name two plans that build one after the other, through after, a chain or a shared file, naming the check and both plans, why, and the next step; the record is unchanged" {
  refused_as full "full apply" "$(r2_two_plans '["P2.1"]' '["src/d.txt"]')"
  r211_named C2 P2.1 P2.2
  # The same through a shared file, with no after.
  refused_as full "full apply" "$(r2_two_plans '[]' '["src/c.txt"]')"
  r211_named C2 P2.1 P2.2
  # Through a chain: P2.3 after P2.2 after P2.1, the rules naming P2.1 and P2.3.
  refused_as full "full apply" "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]},
      {id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: ["P2.2"], tasks: ["print"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is printed", check: "C2", plan: "P2.3"}]')"
  r211_named C2 P2.1 P2.3
}

@test "R211 R216: --add and --patch refuse the same, naming their mode" {
  refused_as add "--add" "$(add_with '.plans += [{id: "P3.2", phase: "P3", title: "Refund mail", reqs: ["R3"], files: ["src/r2.txt"], after: ["P3.1"]}]
    | .rules = [{req: "R3", text: "a refund is paid", check: "C3", plan: "P3.1"}, {req: "R3", text: "a refund is mailed", check: "C3", plan: "P3.2"}]')"
  r211_named C3 P3.1 P3.2
  refused_as patch "--patch" '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/d.txt"], "after": ["P2.1"]}],
    "rules": [{"req": "R2", "text": "a receipt is shown", "check": "C2", "plan": "P2.1"}, {"req": "R2", "text": "a receipt is mailed", "check": "C2", "plan": "P2.2"}]}'
  r211_named C2 P2.1 P2.2
}

@test "R211 R215: no refusal when the check's rules name one plan or none, when one of the two plans is done, or when the check belongs to a requirement of another milestone; a retired rule counts for nothing" {
  # Both rules name P2.1: one owner.
  replan_accepted full "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is mailed", check: "C2", plan: "P2.1"}]')"
  # No rule names a plan.
  replan_accepted full "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]}]
    | .rules += [{req: "R2", text: "a receipt is mailed", check: "C2"}]')"
  # P1.1 is done, P1.2 builds after it: C1's rules may name both.
  replan_accepted full "$(full_with '.rules = [.rules[] | if .req == "R1" then . + {plan: "P1.1"} else . end] + [{req: "R1", text: "a card is refused", check: "C1", plan: "P1.2"}]')"
  # A retired rule naming the later plan is nothing.
  replan_edit '(.requirements[] | select(.id == "R2")).rules += [{text: "a receipt is faxed", check: "C2", plan: "P2.2", retired: "fax dropped"}]'
  replan_accepted full "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end]')"
  [ "$(replan_part '[.requirements[] | select(.id == "R2")][0].rules | map([.plan, .retired])')" = '[["P2.1",null],["P2.2","fax dropped"]]' ]
  # A check of another milestone's requirement: R2 moves to M0, its rules name P2.1 and P2.2 beside each other.
  replan_edit '.shipped = [{id: "M0", title: "Old", at: "2026-01-01T00:00:00Z"}] | (.requirements[] | select(.id == "R2")) |= (.milestone = "M0" | .rules = [{text: "a receipt is shown", check: "C2", plan: "P2.1"}, {text: "a receipt is mailed", check: "C2", plan: "P2.2"}])
    | (.plans[] | select(.id == "P2.2")).after = []'
  replan_accepted patch '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/d.txt"], "after": []}]}'
}

@test "R212 R216: every mode refuses a requirement whose live rules name a plan on only some, naming the requirement and the counts, with its next step; the record is unchanged" {
  refused_as full "full apply" "$(full_with '.rules += [{req: "R1", text: "a card is refused", check: "C1", plan: "P1.1"}]')"
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  last_line_is "$MIXED_NEXT"
  refused_as add "--add" "$(add_with '.rules += [{req: "R3", text: "a refund is mailed", check: "C3", plan: "P3.1"}]')"
  [[ "$output" == *"R3: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  last_line_is "$MIXED_NEXT"
  refused_as patch "--patch" '{"rules": [{"req": "R1", "text": "a card is refused", "check": "C1", "plan": "P1.1"}]}'
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  last_line_is "$MIXED_NEXT"
}

@test "R212: a patch reword that names a plan on one rule and leaves the requirement mixed is refused; every rule naming a plan, or none, is accepted; retired rules are not counted" {
  replan_accepted patch '{"rules": [{"req": "R1", "text": "a card is refused", "check": "C1"}]}'
  refused_as patch "--patch" '{"rules": [{"rule": "R1.1", "plan": "P1.1"}]}'
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  replan_accepted patch '{"rules": [{"rule": "R1.1", "plan": "P1.1"}, {"rule": "R1.2", "plan": "P1.1"}]}'
  [ "$(replan_part '[.requirements[] | select(.id == "R1")][0].rules | map(.plan)')" = '["P1.1","P1.1"]' ]
  # Taking the plan off one rule by a reword leaves the requirement mixed.
  replan_edit '(.requirements[] | select(.id == "R1")).rules[1] |= del(.plan)'
  refused_as patch "--patch" '{"rules": [{"rule": "R1.2", "text": "a card is refused by name"}]}'
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  # A retired rule without a plan beside live rules with one.
  replan_edit '(.requirements[] | select(.id == "R1")).rules |= [.[0], {text: "an old rule", check: "C1", retired: "gone"}]'
  replan_accepted patch '{"rules": [{"req": "R1", "text": "a card is refused", "check": "C1", "plan": "P1.1"}]}'
  [ "$(replan_part '[.requirements[] | select(.id == "R1")][0].rules | map([.plan, .retired])')" = '[["P1.1",null],[null,"gone"],["P1.1",null]]' ]
}

@test "R215 R216: every mode refuses a check whose rules name two plans that build beside each other (a shared wave), naming the check and both plans, the race, and the next step; the record is unchanged" {
  refused_as full "full apply" "$(r2_two_plans '[]' '["src/d.txt"]')"
  beside_named C2 P2.1 P2.2
  refused_as add "--add" "$(add_with '.plans += [{id: "P3.2", phase: "P3", title: "Refund mail", reqs: ["R3"], files: ["src/r2.txt"], after: []}]
    | .rules = [{req: "R3", text: "a refund is paid", check: "C3", plan: "P3.1"}, {req: "R3", text: "a refund is mailed", check: "C3", plan: "P3.2"}]')"
  beside_named C3 P3.1 P3.2
  refused_as patch "--patch" '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/d.txt"], "after": []}],
    "rules": [{"req": "R2", "text": "a receipt is shown", "check": "C2", "plan": "P2.1"}, {"req": "R2", "text": "a receipt is mailed", "check": "C2", "plan": "P2.2"}]}'
  beside_named C2 P2.1 P2.2
}

@test "R215 R216: a pair in an earlier and a later wave with no tie between them is refused with the ordered words and the wave reason" {
  # P2.3 shares nothing with P2.1; P2.2 builds after P2.3, so P2.1 is in wave 1 and P2.2 in wave 2.
  refused_as full "full apply" "$(full_with '.plans += [{id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: [], tasks: ["print"]},
      {id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.3"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is mailed", check: "C2", plan: "P2.2"}]')"
  [[ "$output" == *"C2 is owned by two plans that build one after the other (P2.1 builds in an earlier wave than P2.2): P2.1 and P2.2; the earlier plan's mutation step would find C2 red on unbroken code"* ]] || { echo "$output"; false; }
  last_line_is "$TWO_OWNER_NEXT"
}

@test "R215 R216: a pair with one plan blocked is refused like an open pair, with and without a blocked plan the later one waits for" {
  # P2.1 blocked, P2.2 beside it.
  replan_edit '(.plans[] | select(.id == "P2.1")) |= (.status = "blocked" | .note = "waiting")'
  refused_as full "full apply" "$(r2_two_plans '[]' '["src/d.txt"]')"
  beside_named C2 P2.1 P2.2
  # P2.3 blocked too, and P2.2 waits for it: P2.1 is in an earlier wave.
  replan_edit '.plans += [{id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: [], status: "blocked", note: "waiting", tasks: ["print"]}]'
  refused_as full "full apply" "$(full_with '.plans += [{id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: [], tasks: ["print"]},
      {id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.3"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is mailed", check: "C2", plan: "P2.2"}]')"
  [[ "$output" == *"P2.1 builds in an earlier wave than P2.2"* ]] || { echo "$output"; false; }
  last_line_is "$TWO_OWNER_NEXT"
}
