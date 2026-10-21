#!/usr/bin/env bats
# R179 (P128; docs/loop.md, The cycle): one kernel command, vbw loop next
# --json, does every step that needs no agent and returns the first that does.
# For the next waiting item it opens a milestone titled with the item (vbw
# milestone start, or the current milestone renamed when it has no
# requirements), adds the item's recorded text as that milestone's one
# requirement ([auto], or [human] when the backlog text starts with "[human] ")
# and marks the item in progress; it approves by delegation when vbw next says
# approve; it runs vbw ship when vbw next says ship; it marks a shipped item's
# backlog entry done; it answers done when the list is finished. Steps that
# need an agent (plan, build, fix, qa) or a proof come back as vbw next gives
# them, with the same detail, rigor, effort and profile fields. vbw next itself
# stays a pure reading of the record. The loop never calls vbw approve; a run
# it opens carries the same lease as any run and ends through vbw run end. L1.

load helper
load loop-helper
load fixture-helper

setup_file() { fixture_build loop loop_project; }
setup() { fixture_copy loop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# same_as_next: the loop step's last answer is what vbw next answers, and vbw next changes nothing.
same_as_next() {
  local before
  before=$(record_sum)
  VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null > "$TEST_ROOT/next.json"
  [ "$(record_sum)" = "$before" ] || { echo "vbw next wrote the record"; return 1; }
  jq -e --slurpfile n "$TEST_ROOT/next.json" '.action == $n[0].action and .instruction == $n[0].instruction and .detail == $n[0].detail' "$TEST_ROOT/step.json" \
    || { echo "loop step: $(cat "$TEST_ROOT/step.json")"; echo "vbw next: $(cat "$TEST_ROOT/next.json")"; return 1; }
}

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }

@test "R179: the first step opens the item's milestone (renamed when empty), adds its requirement, marks it in progress, and returns plan with the router's fields" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.milestone.id == "M2" and .milestone.title == "Visitors can read a greeting" and .milestone.status == "active"' .vbw/record.json
  jq -e '[.requirements[] | select(.milestone == "M2")] | length == 1 and .[0].text == "Visitors can read a greeting" and .[0].proof == "auto"' .vbw/record.json
  grep -q '^- R2 \[auto\] Visitors can read a greeting$' .vbw/spec.md
  jq -e '.todos[] | select(.id == "T1") | .status == "in_progress"' .vbw/record.json
  jq -e '.loop.items[0] | .status == "in_progress" and .milestone == "M2" and (.head | test("^[0-9a-f]{40}$"))' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  jq -e '.loop.items[1].status == "waiting"' .vbw/record.json
  jq -e '.gate == false and (.detail | type == "object") and (.rigor | type == "object") and (.effort | type == "object") and (.profile | type == "object")
    and (.requirements | length == 1) and (.next_phase | type == "number") and .loop.item.id == "T1"' "$TEST_ROOT/step.json" || { cat "$TEST_ROOT/step.json"; false; }
  same_as_next
  # The step is idempotent: run again, nothing more is opened or added.
  [ "$(step)" = plan ]
  jq -e '[.requirements[] | select(.milestone == "M2")] | length == 1' .vbw/record.json
}

@test "R179: a backlog item starting with [human] becomes a [human] requirement" {
  "$VBW" todo add "[human] The greeting feels friendly" > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop start T3 --no-ceiling > /dev/null
  jq -e '.loop.items[0].proof == "human" and .loop.items[0].text == "[human] The greeting feels friendly"' .vbw/record.json
  [ "$(step)" = plan ]
  jq -e '[.requirements[] | select(.milestone == "M2")] | length == 1 and .[0].proof == "human" and .[0].text == "The greeting feels friendly"' .vbw/record.json
  grep -q '^- R2 \[human\] The greeting feels friendly$' .vbw/spec.md
}

@test "R179: through one item from milestone to ship: approve by delegation, build, prove, ship, backlog done, then the next item's milestone" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" "$(jq -r .next_phase "$TEST_ROOT/step.json" | sed 's/^/P/')"
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.decisions[-1].text | test("approved by the loop")' .vbw/record.json
  jq -e '.detail.plans == ["P2.1"] and .loop.item.id == "T1"' "$TEST_ROOT/step.json"
  same_as_next
  # A run the loop's session opens carries the same lease as any run and ends through vbw run end.
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  jq -e '.lease | .kind == "build" and .session == "s1" and .files == ["src/greet.txt"] and (.run | startswith("build-")) and (.started_at | type == "string")' .vbw/record.json
  [ "$(step)" = run ]
  printf 'hello\n' > src/greet.txt
  "$VBW" commit P2.1 "feat(greet): hello" > /dev/null
  "$VBW" plan done P2.1 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  jq -e '.lease == null and (.costs.runs | length) == 1 and .costs.runs[0].kind == "build"' .vbw/record.json
  [ "$(step)" = prove ] || { cat "$TEST_ROOT/step.json"; false; }
  same_as_next
  loop_prove
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  # The ship happened, T1 is done, and the second item's milestone is open.
  jq -e '.shipped | length == 2 and .[1].id == "M2" and .[1].title == "Visitors can read a greeting"' .vbw/record.json
  jq -e '.todos[] | select(.id == "T1") | .status == "done"' .vbw/record.json
  jq -e '.loop.items[0] | .status == "shipped" and .milestone == "M2"' .vbw/record.json
  jq -e '.milestone.id == "M3" and .milestone.title == "Visitors can read a farewell" and .milestone.status == "active"' .vbw/record.json
  jq -e '[.requirements[] | select(.milestone == "M3")] | length == 1 and .[0].text == "Visitors can read a farewell"' .vbw/record.json
  jq -e '.todos[] | select(.id == "T2") | .status == "in_progress"' .vbw/record.json
  jq -e '.loop.item.id == "T2" and .loop.item.n == 2 and .loop.item.of == 2' "$TEST_ROOT/step.json"
  # The loop never called vbw approve: the only "Contract approved:" decision is the fixture's own.
  jq -e '[.decisions[] | select(.text | startswith("Contract approved:"))] | length == 1' .vbw/record.json
  [ -z "$(git status --porcelain -- .vbw)" ]
}

@test "R179: done when the list is finished, and the loop is recorded as ended" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  [ "$(step)" = prove ]
  loop_prove
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.reason | test("end of (the )?list")' "$TEST_ROOT/step.json"
  jq -e '.milestone.status == "shipped" and .loop.ended.reason != null and (.loop.ended.at | type == "string")' .vbw/record.json
  jq -e '.todos[] | select(.id == "T1") | .status == "done"' .vbw/record.json
  [ "$(step)" = done ]
  [ "$(next_action)" = milestone ]
}
