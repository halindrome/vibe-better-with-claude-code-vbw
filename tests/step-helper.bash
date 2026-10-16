#!/usr/bin/env bash
# Shared by the R190 step tests (tests/step-*.bats, L1): a small project with an
# approved contract, the clone's step history and the kernel's step note.
#
# The history: $(git common dir)/vbw/steps.json, {"steps": [{kind, run,
# started_at, ended_at, seconds, parts?}]}. The note: .vbw/runtime/step.json,
# written only by the kernel while a step runs: {kind, run, session, pid,
# started_at, ids, doing, parts: {done, total} | null, proof: {done, total} |
# null, first_end, end, late}. A time is UTC ISO 8601 to the second; first_end
# and end are null when there is no basis.

# step_project: a git project, spec R1, one express phase P1 with three plans
# (P1.1 src/a.txt, P1.2 src/b.txt, P1.3 src/c.txt), check C1 (true), approved.
step_project() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'c\n' > src/c.txt
  step_edit '.checks = [{id: "C1", req: "R1", run: ["true"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1"], milestone: "M1", tier: "express"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["src/a.txt"], after: [], status: "planned"},
                {id: "P1.2", phase: "P1", title: "B", reqs: ["R1"], files: ["src/b.txt"], after: [], status: "planned"},
                {id: "P1.3", phase: "P1", title: "C", reqs: ["R1"], files: ["src/c.txt"], after: [], status: "planned"}]'
  git add -A
  git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  STEPS="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/steps.json"
  NOTE="$PROJECT/.vbw/runtime/step.json"
  export STEPS NOTE
}

# step_edit FILTER: change the record as a test fixture.
step_edit() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" \
    .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# step_seed KIND SECONDS PARTS COUNT: COUNT finished steps of KIND, each SECONDS
# long, with PARTS parts ("-" records none), appended to the history.
step_seed() {
  mkdir -p "$(dirname "$STEPS")"
  [ -f "$STEPS" ] || printf '{"steps": []}\n' > "$STEPS"
  jq --arg k "$1" --argjson s "$2" --arg p "$3" --argjson n "$4" '
    .steps += [range(0; $n) as $i | {kind: $k, run: "\($k)-seed-\(.steps | length)-\($i)",
      started_at: "2026-01-01T00:00:00Z", ended_at: ("2026-01-01T00:00:00Z" | fromdateiso8601 + $s | todateiso8601), seconds: $s}
      + (if $p == "-" then {} else {parts: ($p | tonumber)} end)]' "$STEPS" > "$TEST_ROOT/steps.json"
  cp "$TEST_ROOT/steps.json" "$STEPS"
}

# step_back SECONDS: the running step started SECONDS earlier than it did: the
# lease's start in the record and the note's start and end times move back.
step_back() {
  step_edit ".lease.started_at = (.lease.started_at | fromdateiso8601 - $1 | todateiso8601)"
  jq --argjson s "$1" 'def back: if . == null then null else fromdateiso8601 - $s | todateiso8601 end
    | .started_at |= back | .first_end |= back | .end |= back' "$NOTE" > "$TEST_ROOT/note.json"
  cp "$TEST_ROOT/note.json" "$NOTE"
}

# step_secs FIELD: seconds from the note's started_at to its FIELD.
step_secs() {
  jq -r --arg f "$1" '(.[$f] | fromdateiso8601) - (.started_at | fromdateiso8601)' "$NOTE"
}

# step_finish PLAN FILE: commit a change to the plan's file and record it done.
step_finish() {
  printf 'done\n' >> "$2"
  "$VBW" commit "$1" "feat(pay): $1" > /dev/null
  "$VBW" plan "done" "$1" > /dev/null
}
