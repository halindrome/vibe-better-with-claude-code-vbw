#!/usr/bin/env bats
# R156 (docs/workflows.md): a requirement of a shipped milestone is reopened
# when its text or its proof type changes in .vbw/spec.md: vbw spec sync moves
# it to the current milestone, status open. A full vbw apply whose new phase
# covers it is then accepted, and the shipped milestone's phase that covered it
# keeps its id, title, requirements, goal, criteria, tier and every plan with
# its status. A full apply covering a requirement of a shipped milestone that
# was not reopened is still refused, naming the requirement and its milestone. L1.

load helper
load replan-helper
load fixture-helper

# M1 shipped: P1 covers R1 (plan P1.1 done, R1 proven); R2 stayed in M1,
# proven, with no phase. R3 belongs to the active milestone M2.
reopen_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Visitors read the first note\n- R2 [auto] Visitors read the second note\n- R3 [auto] Visitors read the third note\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Notes", reqs: ["R1"], goal: "Notes can be read", criteria: ["the first note shows"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "First", reqs: ["R1"], files: ["src/n1.txt"], after: [], tasks: ["first"]}],
    checks: []}' | "$VBW" apply > /dev/null
  replan_edit '.shipped = [{id: "M1", title: "First", at: "2026-10-01T09:00:00Z"}]
    | .milestone = {id: "M2", title: "Second", status: "active"}
    | .requirements |= map(if .id == "R3" then .milestone = "M2" else .milestone = "M1" | .status = "proven" end)
    | (.plans[] | select(.id == "P1.1")).status = "done"'
}

setup_file() { fixture_build reopen reopen_project; }
setup() { fixture_copy reopen; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# shipped: the shipped phase P1 and its plans, every field.
shipped() { replan_part '{phase: (.phases[] | select(.id == "P1")), plans: [.plans[] | select(.phase == "P1")]}'; }

# again REQ...: a full apply document with the new phase P3 for REQ...
again() {
  jq -nc '$ARGS.positional as $q | {phases: [{id: "P3", title: "Notes again", reqs: $q, goal: "Notes read better", criteria: ["notes read better"], tier: "standard"}],
    plans: [{id: "P3.1", phase: "P3", title: "Again", reqs: $q, files: ["src/n3.txt"], after: [], tasks: ["again"]}], checks: []}' --args "$@"
}

@test "R156: a changed text reopens a shipped requirement: vbw spec sync moves it to the current milestone, open" {
  sed -i.bak 's/Visitors read the first note/Visitors read the first note in large print/' .vbw/spec.md
  "$VBW" spec sync > /dev/null
  [ "$(replan_part '.requirements[] | select(.id == "R1") | {milestone, status}')" = '{"milestone":"M2","status":"open"}' ]
}

@test "R156: a full apply whose new phase covers a requirement reopened by a text change is accepted" {
  sed -i.bak 's/Visitors read the first note/Visitors read the first note in large print/' .vbw/spec.md
  "$VBW" spec sync > /dev/null
  replan_accepted full "$(again R3 R1)"
  [ "$(replan_part '[.phases[] | select(.milestone == "M2") | .id]')" = '["P3"]' ]
}

@test "R156: a full apply whose new phase covers a requirement reopened by a proof type change is accepted" {
  sed -i.bak 's/R1 \[auto\]/R1 [human]/' .vbw/spec.md
  "$VBW" spec sync > /dev/null
  [ "$(replan_part '.requirements[] | select(.id == "R1") | {milestone, status, proof}')" = '{"milestone":"M2","proof":"human","status":"open"}' ]
  replan_accepted full "$(again R1)"
  [ "$(replan_part '[.phases[] | select(.milestone == "M2") | .id]')" = '["P3"]' ]
}

@test "R156: after that apply the shipped phase keeps its id, title, requirements, goal, criteria, tier and every plan with its status" {
  local before
  before=$(shipped)
  sed -i.bak 's/Visitors read the first note/Visitors read the first note in large print/' .vbw/spec.md
  "$VBW" spec sync > /dev/null
  replan_accepted full "$(again R1)"
  [ "$(shipped)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(shipped)"; false; }
  replan_part '.phases[] | select(.id == "P1") | .tier == "standard" and .reqs == ["R1"]' | grep -qx true
}

@test "R156: a full apply covering a shipped requirement that was not reopened is refused, naming the requirement and its milestone" {
  replan_refused full "$(again R3 R2)"
  [[ "$output" == *"R2"* && "$output" == *"M1"* ]] || { echo "$output"; false; }
  replan_refused full "$(again R1)"
  [[ "$output" == *"R1"* && "$output" == *"M1"* ]] || { echo "$output"; false; }
}
