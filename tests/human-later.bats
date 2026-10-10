#!/usr/bin/env bats
# R161 (docs/proof.md, docs/next.md): a [human] requirement the user answered
# "Skip for now" (vbw req skip) can move to the next milestone when it is all
# that holds up the release. The three answers stay (Works, Something's wrong,
# Skip for now). When the only unfinished requirements are skipped [human] ones,
# vbw next offers the ship with them named (detail.later), so VBW asks once:
# ship now and judge them in the next milestone, or judge them now; it does not
# offer it while other work remains or when nothing was skipped. Judging now
# changes nothing. vbw ship then ships, its decision counting only what was
# proven or accepted and naming the moved requirements; vbw milestone start
# moves each into the new milestone with the same id, text, proof type, rules
# and history, status open, and vbw next offers it for judgement. Its spec line
# is unchanged and vbw spec sync neither resets nor duplicates it. [auto]
# requirements never move, nor does a [human] one with an open fix from the
# user's rejection. L1.

load helper
load rigor-helper

# R1 [auto] proven, R2 [human] built and QA passed: next asks to accept R2. R2
# has a history: a rejection whose fix was done, and a decision naming it.
setup() {
  rigor_flow_setup human
  rigor_flow_build
  "$VBW" qa record P1 pass quick > /dev/null
  "$VBW" req reject R2 "the greeting is too small" > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" fix done F1 > /dev/null
  "$VBW" decide "R2 is judged by eye" "a person reads the greeting" > /dev/null
}

teardown() { vbw_teardown; }

next_json() { "$VBW" next --json < /dev/null; }

# r2: the requirement R2 as the record keeps it, without its milestone and status.
r2() { jq -cS '.requirements[] | select(.id == "R2") | del(.milestone, .status, .skipped, .later)' .vbw/record.json; }
# history: R2's fixes, decisions and the checks. The ship's own decision names
# R2 as moved (the test above requires it), so it is not part of R2's history.
history() { jq -cS '{fixes: [.fixes[] | select(.req == "R2")], decisions: [.decisions[] | select((.text | contains("R2")) and (.text | startswith("Shipped ") | not))], checks}' .vbw/record.json; }

@test "R161: the verify and vibe skills keep the three answers, and Skip for now is recorded with vbw req skip" {
  local f
  for f in "$PLUGIN_ROOT/skills/verify/SKILL.md" "$PLUGIN_ROOT/skills/vibe/SKILL.md"; do
    grep -q '"Works"' "$f" && grep -q '"Something'"'"'s wrong"' "$f" && grep -q '"Skip for now"' "$f" || { echo "$f lost one of the three answers"; false; }
    grep -q 'Skip for now' "$f" && grep -q 'vbw req skip' "$f" || { echo "$f does not record a skip with vbw req skip"; false; }
  done
}

@test "R161: with nothing skipped, vbw next asks for the verdict as before" {
  next_json | jq -e '.action == "accept" and (.detail.requirements == ["R2"]) and (.detail.later == null)'
}

@test "R161: when only skipped [human] requirements remain, vbw next offers to ship and judge them in the next milestone" {
  run "$VBW" req skip R2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  next_json | jq -e '.action == "ship" and .gate == true and .detail.later == ["R2"]' || { next_json; false; }
  next_json | jq -r .instruction | grep -q 'R2' || { next_json; false; }
}

@test "R161: no such offer while other work remains" {
  "$VBW" req skip R2 > /dev/null
  printf -- '- R3 [auto] Visitors can read note number 3\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  next_json | jq -e '.action != "ship" and (.detail.later == null)' || { next_json; false; }
}

@test "R161: judging now changes nothing in the record" {
  "$VBW" req skip R2 > /dev/null
  local before
  before=$(cksum < .vbw/record.json)
  next_json > /dev/null
  [ "$(cksum < .vbw/record.json)" = "$before" ]
  run "$VBW" req accept R2
  [ "$status" -eq 0 ]
  next_json | jq -e '.action == "ship" and (.detail.later == null or .detail.later == [])'
}

@test "R161: shipping now counts only what was proven or accepted and names the moved requirement" {
  "$VBW" req skip R2 > /dev/null
  run "$VBW" ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.milestone.status == "shipped"' .vbw/record.json
  local text
  text=$(jq -r '.decisions[-1].text' .vbw/record.json)
  [[ "$text" == "Shipped M1"* ]] || { echo "$text"; false; }
  [[ "$text" == *": 1 requirement"* ]] || { echo "the decision does not count only R1: $text"; false; }
  [[ "$text" == *"R2"* ]] || { echo "the decision does not name R2: $text"; false; }
}

@test "R161: after vbw milestone start the moved requirement belongs to the new milestone, open, with the same id, text, proof, rules and history" {
  "$VBW" req skip R2 > /dev/null
  local req hist
  req=$(r2)
  hist=$(history)
  "$VBW" ship > /dev/null
  "$VBW" milestone start "Second" > /dev/null
  jq -e '.requirements[] | select(.id == "R2") | .milestone == "M2" and .status == "open" and .proof == "human"' .vbw/record.json
  [ "$(r2)" = "$req" ] || { printf 'before: %s\nafter:  %s\n' "$req" "$(r2)"; false; }
  [ "$(history)" = "$hist" ] || { printf 'before: %s\nafter:  %s\n' "$hist" "$(history)"; false; }
  jq -e '[.requirements[] | select(.id == "R1")][0].milestone == "M1"' .vbw/record.json
}

@test "R161: in the new milestone vbw next offers the moved requirement for judgement" {
  "$VBW" req skip R2 > /dev/null
  "$VBW" ship > /dev/null
  "$VBW" milestone start "Second" > /dev/null
  next_json | jq -e '.action == "accept" and (.detail.requirements | index("R2") != null)' || { next_json; false; }
}

@test "R161: the spec line stays as it was, and vbw spec sync neither resets nor duplicates the moved requirement" {
  local line
  line=$(grep '^- R2 ' .vbw/spec.md)
  "$VBW" req skip R2 > /dev/null
  "$VBW" ship > /dev/null
  "$VBW" milestone start "Second" > /dev/null
  [ "$(grep '^- R2 ' .vbw/spec.md)" = "$line" ]
  local before
  before=$(jq -cS '.requirements[] | select(.id == "R2")' .vbw/record.json)
  "$VBW" spec sync > /dev/null
  [ "$(jq '[.requirements[] | select(.id == "R2")] | length' .vbw/record.json)" -eq 1 ]
  [ "$(jq -cS '.requirements[] | select(.id == "R2")' .vbw/record.json)" = "$before" ]
}

@test "R161: an [auto] requirement is never skipped or moved" {
  run "$VBW" req skip R1
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  jq -e '.requirements[] | select(.id == "R1") | .milestone == "M1" and (has("skipped") | not)' .vbw/record.json
}

@test "R161: a [human] requirement with an open fix from the user's rejection does not move" {
  "$VBW" req reject R2 "still too small" > /dev/null
  "$VBW" req skip R2 > /dev/null 2>&1 || true
  next_json | jq -e '.action != "ship"' || { next_json; false; }
  run "$VBW" ship
  [ "$status" -ne 0 ]
  jq -e '.requirements[] | select(.id == "R2") | .milestone == "M1"' .vbw/record.json
}
