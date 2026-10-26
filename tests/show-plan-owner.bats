#!/usr/bin/env bats
# R209 (D504; docs/workflows.md, docs/proof.md): one definition of a plan's own
# rules lives in the kernel (own_rules in VBW_JQ_DEFS, plugin/lib/record.sh) and
# every reader uses it: owed_rules is built on it, the task break of vbw mutate
# takes its checks from it, and vbw show plan marks what is another plan's from
# it. "R209 kernel" cases: own_rules and owed_rules on the record, and the
# mutate code's use of them (plan P170.1). "R209 show" cases: the marks vbw show
# plan prints on a sibling plan's rule (" [Q's, ORDER]") and on a check only
# other plans' rules point at (" [Q's: red until it is built, not this plan's to
# pass]"), the --json fields, the agreement of the two readers, and the unchanged
# listing of a project whose rules name no plan (plan P170.2). L1: the kernel on
# fixture projects, built once per file.
#
# The fixture: R1 has P1.1 (greet.sh, rule R1.1 -> C1) and P1.2 (shout.sh, after
# P1.1, rule R1.2 -> C2). R2 has P1.3 (a.sh, R2.1 -> C3), P1.4 (b.sh, R2.2 -> C4),
# P1.5 (c.sh, after P1.4, R2.3 -> C4) and a rule naming no plan (R2.4 -> C5). R3
# is [human], served by P1.6. Build waves: [P1.1 P1.3 P1.4 P1.6], [P1.2 P1.5].

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] greet.sh Ana prints Hello, Ana! and shout.sh Ana prints HELLO, ANA!\n- R2 [auto] three helpers\n- R3 [human] it looks nice\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'echo "Hello, $1!"\n' > greet.sh
  printf 'echo todo\n' > shout.sh
  printf 'echo a\n' > a.sh
  printf 'echo b\n' > b.sh
  printf 'echo c\n' > c.sh
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ]\n' > test_greet.sh
  printf '[ "$(sh shout.sh Ana)" = "HELLO, ANA!" ]\n' > test_shout.sh
  printf '[ "$(sh a.sh)" = a ]\n' > test_a.sh
  printf '[ "$(sh b.sh)" = b ] && [ "$(sh c.sh)" = c ]\n' > test_bc.sh
  printf 'true\n' > test_any.sh
  jq -nc '{phases: [{id: "P1", title: "Greet", reqs: ["R1", "R2", "R3"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "greet", reqs: ["R1"], files: ["greet.sh"], after: [], role: "dev", tasks: ["greet prints Hello, NAME!"]},
            {id: "P1.2", phase: "P1", title: "shout", reqs: ["R1"], files: ["shout.sh"], after: ["P1.1"], role: "dev", tasks: ["shout prints HELLO, NAME!"]},
            {id: "P1.3", phase: "P1", title: "a", reqs: ["R2"], files: ["a.sh"], after: [], role: "dev", tasks: ["a"]},
            {id: "P1.4", phase: "P1", title: "b", reqs: ["R2"], files: ["b.sh"], after: [], role: "dev", tasks: ["b"]},
            {id: "P1.5", phase: "P1", title: "c", reqs: ["R2"], files: ["c.sh"], after: ["P1.4"], role: "dev", tasks: ["c"]},
            {id: "P1.6", phase: "P1", title: "nice", reqs: ["R3"], files: ["README.md"], after: [], role: "dev", tasks: ["nice"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "test_greet.sh"], files: ["test_greet.sh"]},
             {id: "C2", req: "R1", run: ["sh", "test_shout.sh"], files: ["test_shout.sh"]},
             {id: "C3", req: "R2", run: ["sh", "test_a.sh"], files: ["test_a.sh"]},
             {id: "C4", req: "R2", run: ["sh", "test_bc.sh"], files: ["test_bc.sh"]},
             {id: "C5", req: "R2", run: ["sh", "test_any.sh"], files: ["test_any.sh"]}],
    rules: [{req: "R1", text: "a name is greeted", check: "C1", plan: "P1.1"},
            {req: "R1", text: "shout.sh prints the greeting in capitals", check: "C2", plan: "P1.2"},
            {req: "R2", text: "a prints a", check: "C3", plan: "P1.3"},
            {req: "R2", text: "b prints b", check: "C4", plan: "P1.4"},
            {req: "R2", text: "c prints c", check: "C4", plan: "P1.5"},
            {req: "R2", text: "anything goes", check: "C5"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(greet): start"
  "$VBW" approve > /dev/null
}

# A project whose rules name no plan: the listing must stay exactly today's.
noplan_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay and gets more\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo nothing yet\n' > src/more.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  printf '[ "$(sh src/more.sh)" = more ]\n' > tests/more.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay", "log the payment"]},
            {id: "P1.2", phase: "P1", title: "More", reqs: ["R1"], files: ["src/more.sh"], after: ["P1.1"], role: "dev", tasks: ["more"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R1", run: ["sh", "tests/more.sh"], files: ["tests/more.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "more prints more", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() {
  fixture_build built built_project
  fixture_build noplan noplan_project
}
setup() { fixture_copy built; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
# defs JQ: run JQ on the record with the kernel's jq definitions (VBW_JQ_DEFS).
defs() { vbw_kernel 'jq -c "$VBW_JQ_DEFS"'"'$1'"' "$VBW_RECORD"'; }
# own PLAN / owed PLAN: the kernel's own_rules and owed_rules, compact JSON.
own() { defs "own_rules(\"$1\")"; }
owed() { defs "owed_rules(\"$1\")"; }
# same A B: two JSON texts are the same value.
same() { [ "$(printf '%s' "$1" | jq -cS .)" = "$(printf '%s' "$2" | jq -cS .)" ] || { echo "got:  $1"; echo "want: $2"; return 1; }; }
status_of() { edit_record "(.plans[] | select(.id == \"$1\")).status = \"$2\""; }
show() { "$VBW" show plan "$1" < /dev/null; }
# has PLAN LINE: show plan PLAN prints LINE, whole and exact.
has() { show "$1" | grep -qxF -- "$2" || { echo "no line is exactly: $2"; show "$1"; return 1; }; }
# marks PLAN: the ownership marks show plan PLAN prints, if any.
marks() { show "$1" | grep -E "\[P[0-9]+\.[0-9]+'s" || true; }

R11='  R1.1 a name is greeted -> C1'
R12='  R1.2 shout.sh prints the greeting in capitals -> C2'
C1='  C1 (R1) sh test_greet.sh [protects test_greet.sh]'
C2='  C2 (R1) sh test_shout.sh [protects test_shout.sh]'
R22='  R2.2 b prints b -> C4'
R23='  R2.3 c prints c -> C4'
R24='  R2.4 anything goes -> C5'
C3='  C3 (R2) sh test_a.sh [protects test_a.sh]'
C4='  C4 (R2) sh test_bc.sh [protects test_bc.sh]'
C5='  C5 (R2) sh test_any.sh [protects test_any.sh]'
NOT_MINE="red until it is built, not this plan's to pass"

# --- R209 kernel: own_rules and owed_rules (plan P170.1)

@test "R209 kernel: own_rules gives the live rules naming the plan while another plan of the requirement is open, as {req, n, text, check, plan}" {
  same "$(own P1.1)" '[{"req": "R1", "n": 1, "text": "a name is greeted", "check": "C1", "plan": "P1.1"}]'
  same "$(own P1.2)" '[{"req": "R1", "n": 2, "text": "shout.sh prints the greeting in capitals", "check": "C2", "plan": "P1.2"}]'
  same "$(own P1.3)" '[{"req": "R2", "n": 1, "text": "a prints a", "check": "C3", "plan": "P1.3"}]'
  same "$(own P1.6)" '[]'
  same "$(own P9.9)" '[]'
}

@test "R209 kernel: a plan that completes a requirement owns every live rule of it, those naming a done plan and those naming no plan included" {
  status_of P1.1 done
  same "$(own P1.2 | jq -c 'map([.n, .plan])')" '[[1, "P1.1"], [2, "P1.2"]]'
  status_of P1.4 done
  status_of P1.5 done
  same "$(own P1.3 | jq -c 'map([.n, .check, .plan])')" '[[1, "C3", "P1.3"], [2, "C4", "P1.4"], [3, "C4", "P1.5"], [4, "C5", null]]'
}

@test "R209 kernel: own_rules does not depend on the tier; owed_rules is own_rules at standard and deep and nothing at express or without a tier" {
  local mine
  mine=$(own P1.1)
  same "$(owed P1.1)" "$mine"
  edit_record '.phases[0].tier = "deep"'
  same "$(own P1.1)" "$mine"
  same "$(owed P1.1)" "$mine"
  edit_record '.phases[0].tier = "express"'
  same "$(own P1.1)" "$mine"
  same "$(owed P1.1)" '[]'
  edit_record 'del(.phases[0].tier)'
  same "$(own P1.1)" "$mine"
  same "$(owed P1.1)" '[]'
}

@test "R209 kernel: a retired rule is left out of own_rules and the other rules keep their numbers" {
  edit_record '(.requirements[] | select(.id == "R2")).rules[0].retired = "a.sh is gone"'
  same "$(own P1.3)" '[]'
  status_of P1.4 done
  status_of P1.5 done
  same "$(own P1.3 | jq -c 'map(.n)')" '[2, 3, 4]'
}

@test "R209 kernel: the task break takes its checks from own_rules and holds no second definition; its fallback and wording stay" {
  local f="$PLUGIN_ROOT/lib/cmd-mutate.sh"
  grep -q 'own_rules(' "$f" || { echo "cmd-mutate.sh does not use own_rules"; false; }
  ! grep -q '\$others' "$f" || { echo "cmd-mutate.sh still holds its own copy of the owner computation"; false; }
  grep -q 'owns no rule' "$f" || { echo "the 'owns no rule' wording is gone"; false; }
  grep -q 'own_rules(' "$PLUGIN_ROOT/lib/record.sh" || { echo "record.sh does not define own_rules"; false; }
}

# --- R209 show: the marks vbw show plan prints (plan P170.2)

@test "R209 show: a sibling plan's rule is marked with its plan and whether it is built after or before this plan; this plan's own rule is listed as today" {
  has P1.1 "$R12 [P1.2's, built after this plan]"
  has P1.1 "$R11"
  has P1.2 "$R11 [P1.1's, built before this plan]"
  has P1.2 "$R12"
}

@test "R209 show: a plan in the same wave is 'built beside this plan'; a rule naming no plan is listed as today" {
  has P1.3 "$R22 [P1.4's, built beside this plan]"
  has P1.3 "$R23 [P1.5's, built after this plan]"
  has P1.3 "$R24"
  has P1.3 '  R2.1 a prints a -> C3'
}

@test "R209 show: the order is 'done' for a done plan, 'blocked' for a blocked one, and 'built after this plan' when this plan is done and the other open" {
  status_of P1.4 done
  has P1.3 "$R22 [P1.4's, done]"
  status_of P1.5 blocked
  has P1.3 "$R23 [P1.5's, blocked]"
  status_of P1.4 planned
  status_of P1.5 planned
  status_of P1.3 done
  has P1.3 "$R22 [P1.4's, built after this plan]"
  has P1.3 "$R23 [P1.5's, built after this plan]"
}

@test "R209 show: once the other plan is done, the completing plan owns every rule, one naming the done plan included, and nothing is marked" {
  status_of P1.1 done
  has P1.2 "$R11"
  has P1.2 "$R12"
  has P1.2 "$C1"
  has P1.2 "$C2"
  [ -z "$(marks P1.2)" ] || { marks P1.2; false; }
}

@test "R209 show: a check only other plans' rules point at is marked as theirs, red until built; several plans are joined with 'and'" {
  has P1.1 "$C2 [P1.2's: $NOT_MINE]"
  has P1.1 "$C1"
  has P1.2 "$C1 [P1.1's: $NOT_MINE]"
  has P1.2 "$C2"
  has P1.3 "$C4 [P1.4's and P1.5's: $NOT_MINE]"
  has P1.3 "$C3"
  has P1.3 "$C5"
}

@test "R209 show: a retired rule counts for nothing: it stays left out, the addresses keep their places, and a check it alone pointed at is unmarked; a [human] plan shows no mark" {
  edit_record '(.requirements[] | select(.id == "R2")).rules[3].retired = "no longer promised"'
  ! show P1.3 | grep -q 'R2\.4' || { show P1.3; false; }
  has P1.3 "$R22 [P1.4's, built beside this plan]"
  has P1.3 "$C5"
  edit_record '(.requirements[] | select(.id == "R2")).rules[0].retired = "a.sh is gone"'
  has P1.3 "$R23 [P1.5's, built after this plan]"
  has P1.3 "$C3"
  [ -z "$(marks P1.6)" ] || { marks P1.6; false; }
  show P1.6 | grep -qx 'checks:'
}

@test "R209 show: --json keeps today's fields and adds plan, own and order to each rule, own and plans to each check" {
  local j
  j=$("$VBW" show plan P1.1 --json < /dev/null)
  printf '%s' "$j" | jq -e 'keys == ["checks", "commands", "plan", "requirements", "rules", "tier"]' > /dev/null || { printf '%s' "$j" | jq -c keys; false; }
  printf '%s' "$j" | jq -e '.rules == [{n: "R1.1", text: "a name is greeted", check: "C1", plan: "P1.1", own: true},
    {n: "R1.2", text: "shout.sh prints the greeting in capitals", check: "C2", plan: "P1.2", own: false, order: "after"}]' > /dev/null || { printf '%s' "$j" | jq -c .rules; false; }
  printf '%s' "$j" | jq -e '[.checks[] | {id, own, plans}] == [{id: "C1", own: true, plans: null}, {id: "C2", own: false, plans: ["P1.2"]}]
    and all(.checks[]; (keys - ["own", "plans"]) == ["files", "id", "last", "req", "run"])' > /dev/null || { printf '%s' "$j" | jq -c .checks; false; }
  j=$("$VBW" show plan P1.3 --json < /dev/null)
  printf '%s' "$j" | jq -e '[.rules[] | [.n, .plan, .own, .order]] == [["R2.1", "P1.3", true, null], ["R2.2", "P1.4", false, "beside"], ["R2.3", "P1.5", false, "after"], ["R2.4", null, true, null]]' > /dev/null \
    || { printf '%s' "$j" | jq -c .rules; false; }
  printf '%s' "$j" | jq -e '[.checks[] | [.id, .own, .plans]] == [["C3", true, null], ["C4", false, ["P1.4", "P1.5"]], ["C5", true, null]]' > /dev/null || { printf '%s' "$j" | jq -c .checks; false; }
  status_of P1.4 done
  status_of P1.5 blocked
  "$VBW" show plan P1.3 --json < /dev/null | jq -e '[.rules[] | .order] == [null, "done", "blocked", null]' > /dev/null
  status_of P1.3 done
  status_of P1.4 planned
  "$VBW" show plan P1.3 --json < /dev/null | jq -e '[.rules[] | .order] == [null, "after", "blocked", null]' > /dev/null
  status_of P1.1 done
  "$VBW" show plan P1.2 --json < /dev/null | jq -e 'all(.rules[]; .own and (has("order") | not)) and all(.checks[]; .own and (has("plans") | not))' > /dev/null
}

@test "R209 show: the two readers agree: the checks of the rules --json marks own are exactly the checks a task break records, early and completing" {
  local own_checks
  own_checks=$("$VBW" show plan P1.1 --json < /dev/null | jq -c '[.rules[] | select(.own) | .check] | unique')
  [ "$own_checks" = '["C1"]' ] || { echo "$own_checks"; false; }
  # A break no check notices (a survivor) runs every check of the plan's own rules.
  printf 'echo "Hello, $1!" # noted\n' > greet.sh
  run "$VBW" mutate P1.1 task1 "adds a comment" greet.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "$output"; false; }
  [ "$(jq -c '[.plans[] | select(.id == "P1.1") | .mutations[-1].checks | keys[]] | unique' .vbw/record.json)" = "$own_checks" ] || { jq -c '.plans[0].mutations' .vbw/record.json; false; }
  # P1.1 done: P1.2 completes R1, owns both rules, and its task break runs both checks.
  printf 'echo "HELLO, $(printf %%s "$1" | tr a-z A-Z)!"\n' > shout.sh
  git commit -q -am "feat(shout): shout"
  status_of P1.1 done
  own_checks=$("$VBW" show plan P1.2 --json < /dev/null | jq -c '[.rules[] | select(.own) | .check] | unique')
  [ "$own_checks" = '["C1","C2"]' ] || { echo "$own_checks"; false; }
  printf 'echo "HELLO, $(printf %%s "$1" | tr a-z A-Z)!" # noted\n' > shout.sh
  run "$VBW" mutate P1.2 task1 "adds a comment" shout.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "$output"; false; }
  [ "$(jq -c '[.plans[] | select(.id == "P1.2") | .mutations[-1].checks | keys[]] | unique' .vbw/record.json)" = "$own_checks" ] || { jq -c '.plans[1].mutations' .vbw/record.json; false; }
}

@test "R209 show: a project whose rules name no plan prints exactly today's listing" {
  fixture_copy noplan
  local want
  want=$(cat <<'EOF'
P1.1 Pay [planned]
files: src/pay.sh
tasks:
  1. pay
  2. log the payment
requirements:
  R1 [auto] A customer can pay and gets more
rules:
  R1.1 paying prints paid -> C1
  R1.2 more prints more -> C2
tier: standard (the mutation check asks one break per rule)
checks:
  C1 (R1) sh tests/pay.sh [protects tests/pay.sh]
  C2 (R1) sh tests/more.sh [protects tests/more.sh]
EOF
)
  [ "$(show P1.1)" = "$want" ] || { diff <(printf '%s\n' "$want") <(show P1.1); false; }
  want=$(cat <<'EOF'
P1.2 More [planned]
files: src/more.sh
tasks:
  1. more
after: P1.1
requirements:
  R1 [auto] A customer can pay and gets more
rules:
  R1.1 paying prints paid -> C1
  R1.2 more prints more -> C2
tier: standard (the mutation check asks one break per rule)
checks:
  C1 (R1) sh tests/pay.sh [protects tests/pay.sh]
  C2 (R1) sh tests/more.sh [protects tests/more.sh]
EOF
)
  [ "$(show P1.2)" = "$want" ] || { diff <(printf '%s\n' "$want") <(show P1.2); false; }
  "$VBW" show plan P1.1 --json < /dev/null | jq -e 'all(.rules[]; .plan == null and .own == true and (has("order") | not)) and all(.checks[]; .own == true and (has("plans") | not))' > /dev/null
}
