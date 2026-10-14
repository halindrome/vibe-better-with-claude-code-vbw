#!/usr/bin/env bats
# R188 (L1, kernel): a newer requirement can replace an earlier one through the
# Lead's own write. vbw apply (full, --patch and --add) takes an optional
# "supersedes": [{"req": OLD, "by": NEW}], where NEW is a requirement a phase of
# the current milestone covers. OLD is then recorded as superseded by NEW
# (status "superseded", "by": NEW) instead of being left proven: its rules and
# checks leave the contract (so its check files are no longer protected), its
# open fixes close, and its phases and plans stay as history. The change is part
# of the contract the user approves. A superseded requirement never asks for
# proof again. Every malformed or impossible entry is refused and nothing
# changes; the record itself refuses an inconsistent supersession.

load helper

# M1 shipped: P1 covers R1 (plan P1.1 done, R1 proven by C1 on tests/old.sh,
# with an open fix F1); R2 stayed in M1 with no phase. R3 and R4 belong to the
# active milestone M2.
setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'true\n' > tests/old.sh
  printf 'true\n' > tests/new.sh
  printf 'one\n' > src/one.txt
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Visitors read the first note\n- R2 [auto] Visitors read the second note\n- R3 [auto] Visitors read every note\n- R4 [auto] Visitors read the last note\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Notes", reqs: ["R1"], goal: "Notes", criteria: ["notes"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "First", reqs: ["R1"], files: ["src/one.txt"], after: [], tasks: ["first"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}],
    rules: [{req: "R1", text: "the first note shows", check: "C1"}]}' | "$VBW" apply > /dev/null
  jq '.shipped = [{id: "M1", title: "First", at: "2026-10-01T09:00:00Z"}]
    | .milestone = {id: "M2", title: "Second", status: "active"}
    | .requirements |= map(.milestone = (if .id == "R3" or .id == "R4" then "M2" else "M1" end)
        | if .id == "R1" then .status = "proven" else . end)
    | (.plans[] | select(.id == "P1.1")).status = "done"
    | .fixes = [{id: "F1", req: "R1", attempts: 1, status: "open", note: "C1 exit 1"}]' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
}

teardown() { vbw_teardown; }

# doc [EXTRA]: a full plan for M2: P2 covers R3 (plan P2.1, check C2 on tests/new.sh), merged with EXTRA.
doc() {
  local x=${1:-}
  [ -n "$x" ] || x='{}'
  jq -nc --argjson x "$x" '{phases: [{id: "P2", title: "Every note", reqs: ["R3"], goal: "All notes", criteria: ["all notes"], tier: "standard"}],
    plans: [{id: "P2.1", phase: "P2", title: "All", reqs: ["R3"], files: ["src/all.txt"], after: [], tasks: ["all"]}],
    checks: [{id: "C2", req: "R3", run: ["sh", "tests/new.sh"], files: ["tests/new.sh"]}],
    rules: [{req: "R3", text: "every note shows", check: "C2"}]} + $x'
}

SUP='{"supersedes":[{"req":"R1","by":"R3"}]}'

# superseded: R1 is superseded by R3, without rules or checks, its file unprotected, F1 closed, P1 and P1.1 kept.
superseded() {
  jq -e '(.requirements[] | select(.id == "R1")) as $r
    | $r.status == "superseded" and $r.by == "R3" and $r.milestone == "M1" and (($r.rules // []) == [])
      and ([.checks[] | select(.req == "R1")] == []) and any(.checks[]; .id == "C2")
      and ((.protected | index("tests/old.sh")) == null) and ((.protected | index("tests/new.sh")) != null)
      and ((.fixes[] | select(.id == "F1")).status == "closed")
      and any(.phases[]; .id == "P1") and ((.plans[] | select(.id == "P1.1")).status == "done")
      and ((.requirements[] | select(.id == "R2")).status == "open")' .vbw/record.json || { jq -c '{requirements, checks, protected, fixes}' .vbw/record.json; return 1; }
}

# only_r1_r3: R2 and R4 leave the spec, so the contract is complete once R3 is planned.
only_r1_r3() {
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Visitors read the first note\n- R3 [auto] Visitors read every note\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
}

# applied DOC [MODE]: vbw apply (or apply MODE) of DOC succeeds.
applied() {
  local out
  out=$(printf '%s' "$1" | "$VBW" apply ${2:+"$2"} 2>&1) || { echo "vbw apply ${2:-} refused: $out"; return 1; }
}

# refused DOC [MODE]: vbw apply (or apply MODE) of DOC is refused and the record's bytes stay; prints the message.
refused() {
  local before out code=0
  before=$(cksum < .vbw/record.json)
  out=$(printf '%s' "$1" | "$VBW" apply ${2:+"$2"} 2>&1) || code=$?
  [ "$code" -ne 0 ] || { echo "vbw apply ${2:-} accepted: $out"; return 1; }
  [ "$(cksum < .vbw/record.json)" = "$before" ] || { echo "vbw apply ${2:-} changed the record"; return 1; }
  printf '%s\n' "$out"
}

@test "R188: a full apply with supersedes records the old requirement as superseded by the new one: rules and checks gone, files unprotected, fixes closed, history kept" {
  applied "$(doc "$SUP")"
  superseded
}

@test "R188: vbw apply --patch and vbw apply --add take supersedes too" {
  printf '%s' "$(doc)" | "$VBW" apply > /dev/null
  applied "$SUP" --patch
  superseded
  vbw_teardown
  setup
  printf '%s' "$(doc)" | "$VBW" apply > /dev/null
  applied '{"phases":[{"id":"P3","title":"Last","reqs":["R4"],"goal":"Last note","criteria":["last"],"tier":"standard"}],
    "plans":[{"id":"P3.1","phase":"P3","title":"Last","reqs":["R4"],"files":["src/last.txt"],"after":[],"tasks":["last"]}],
    "checks":[{"id":"C3","req":"R4","run":["sh","tests/new.sh"],"files":["tests/new.sh"]}],
    "rules":[{"req":"R4","text":"the last note shows","check":"C3"}],
    "supersedes":[{"req":"R1","by":"R4"}]}' --add
  jq -e '(.requirements[] | select(.id == "R1")) | .status == "superseded" and .by == "R4"' .vbw/record.json || { jq -c .requirements .vbw/record.json; false; }
}

@test "R188: error: supersedes naming an unknown requirement, on either side, is refused and nothing changes" {
  local out
  out=$(refused "$(doc '{"supersedes":[{"req":"R9","by":"R3"}]}')") || { echo "$out"; false; }
  [[ "$out" == *R9* ]] || { echo "$out"; false; }
  out=$(refused "$(doc '{"supersedes":[{"req":"R1","by":"R9"}]}')") || { echo "$out"; false; }
  [[ "$out" == *R9* ]] || { echo "$out"; false; }
}

@test "R188: error: the new requirement must be one a phase of the current milestone covers" {
  local out
  # R2 is an earlier milestone's requirement; R4 is this milestone's but no phase covers it.
  out=$(refused "$(doc '{"supersedes":[{"req":"R1","by":"R2"}]}')") || { echo "$out"; false; }
  [[ "$out" == *R2* ]] || { echo "$out"; false; }
  out=$(refused "$(doc '{"supersedes":[{"req":"R1","by":"R4"}]}')") || { echo "$out"; false; }
  [[ "$out" == *R4* ]] || { echo "$out"; false; }
}

@test "R188: error: a requirement cannot supersede itself, and one a phase of the plan covers cannot be superseded" {
  local out
  out=$(refused "$(doc '{"supersedes":[{"req":"R3","by":"R3"}]}')") || { echo "$out"; false; }
  [[ "$out" == *R3* ]] || { echo "$out"; false; }
  out=$(refused "$(jq -nc '{phases: [{id: "P2", title: "Every note", reqs: ["R3", "R4"], tier: "standard"}],
    plans: [{id: "P2.1", phase: "P2", title: "All", reqs: ["R3", "R4"], files: ["src/all.txt"], after: [], tasks: ["all"]}],
    checks: [{id: "C2", req: "R3", run: ["sh", "tests/new.sh"], files: ["tests/new.sh"]}, {id: "C3", req: "R4", run: ["sh", "tests/new.sh"], files: ["tests/new.sh"]}],
    rules: [{req: "R3", text: "every note shows", check: "C2"}, {req: "R4", text: "the last note shows", check: "C3"}],
    supersedes: [{req: "R4", by: "R3"}]}')") || { echo "$out"; false; }
  [[ "$out" == *R4* ]] || { echo "$out"; false; }
}

@test "R188: error: a requirement already superseded is not superseded again" {
  printf '%s' "$(doc "$SUP")" | "$VBW" apply > /dev/null
  superseded
  local out
  out=$(refused "$SUP" --patch) || { echo "$out"; false; }
  [[ "$out" == *R1* && "$out" == *superseded* ]] || { echo "$out"; false; }
}

@test "R188: error: a malformed supersedes is refused and nothing changes" {
  local bad out
  for bad in '{"supersedes":{"req":"R1","by":"R3"}}' '{"supersedes":[{"req":"R1"}]}' '{"supersedes":[{"by":"R3"}]}' \
    '{"supersedes":[{"req":"R1","by":"R3","why":"x"}]}' '{"supersedes":[{"req":1,"by":"R3"}]}'; do
    out=$(refused "$(doc "$bad")") || { echo "$bad: $out"; false; }
    [[ "$out" == *supersedes* ]] || { echo "$bad: $out"; false; }
  done
}

@test "R188: the supersession is part of the contract: approval is asked again and the changes name it" {
  only_r1_r3
  printf '%s' "$(doc)" | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore: plan"
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  applied "$SUP" --patch
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "approve"' || { echo "$output"; false; }
  vbw_run show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E 'R1' | grep -q 'superseded by R3' || { echo "$output"; false; }
  vbw_run show req R1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | head -n 1 | grep -q 'superseded by R3' || { echo "$output"; false; }
}

@test "R188: a superseded requirement is approved without checks and never asks for proof again" {
  only_r1_r3
  printf '%s' "$(doc "$SUP")" | "$VBW" apply > /dev/null
  jq '(.plans[] | select(.id == "P2.1")).status = "done"' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  printf 'all\n' > src/all.txt
  git add -A && git commit -q -m "chore: plan"
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '(.requirements[] | select(.id == "R1")) | .status == "superseded" and .by == "R3"' .vbw/record.json || { jq -c .requirements .vbw/record.json; false; }
  jq -e '(.requirements[] | select(.id == "R3")).status == "proven"' .vbw/record.json || { jq -c .requirements .vbw/record.json; false; }
  vbw_run next --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.. | strings | select(. == "R1")] | length == 0' || { echo "$output"; false; }
  # A spec sync with R1's text unchanged keeps it superseded.
  vbw_run spec sync
  jq -e '(.requirements[] | select(.id == "R1")) | .status == "superseded" and .by == "R3"' .vbw/record.json || { jq -c .requirements .vbw/record.json; false; }
}

@test "R188: error: the record refuses an inconsistent supersession" {
  printf '%s' "$(doc "$SUP")" | "$VBW" apply > /dev/null
  local edit bad
  for edit in '(.requirements[] | select(.id == "R1")) |= del(.by)' \
    '(.requirements[] | select(.id == "R1")).by = "R9"' \
    '(.requirements[] | select(.id == "R2")).by = "R3"' \
    '.checks += [{id: "C9", req: "R1", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}]'; do
    cp .vbw/record.json "$TEST_ROOT/good.json"
    jq "$edit" "$TEST_ROOT/good.json" > .vbw/record.json
    bad=$(cksum < .vbw/record.json)
    vbw_run todo add "a note"
    [ "$status" -ne 0 ] || { echo "accepted after: $edit"; false; }
    [ "$(cksum < .vbw/record.json)" = "$bad" ] || { echo "wrote after: $edit"; false; }
    cp "$TEST_ROOT/good.json" .vbw/record.json
  done
}
