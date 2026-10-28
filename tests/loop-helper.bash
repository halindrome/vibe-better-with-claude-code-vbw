# shellcheck shell=bash
# Shared fixtures for the loop tests (M25, R178-R180). Load after helper:
#   load helper
#   load loop-helper
# A loop_project has one shipped milestone (M1: R1 proven by C1, tests/notes.sh),
# the active milestone M2 "Next" with no requirements, a status-line figure for
# session s1 ($2.00, 1000 in, 100 out) and two backlog items, T1 and T2, in that
# order. With "human", M1 also had R2 [human], skipped at ship and carried into
# M2 for the user to judge; the backlog items are then T1 and T2 all the same.
# M2's cost baseline holds s1 at $2.00, the same figure a loop started next
# records as its own baseline.

# figures SID USD IN OUT: the session's side file, as the status line writes it.
figures() {
  mkdir -p .vbw/runtime
  jq -nc --arg s "$1" --argjson u "$2" --argjson i "$3" --argjson o "$4" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{session: $s, usd: $u, in: $i, out: $o, at: $at}' > ".vbw/runtime/cost.$1.json"
}

# no_figures: no session has a figure any more.
no_figures() { rm -f .vbw/runtime/cost.*.json; }

# edit_record JQ_EXPR: a hand edit of the record (the glance is dropped so
# readers take the record).
edit_record() {
  jq "$1 | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

# record_sum: a checksum of the record's bytes, to show a command changed nothing.
record_sum() { cksum < .vbw/record.json; }

# project_sum: the record, the spec, git HEAD and the index together.
project_sum() {
  { cat .vbw/record.json .vbw/spec.md; git rev-parse HEAD; git ls-files --stage; } | cksum
}

loop_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p tests src
  {
    printf '# Notes\n\n## Requirements\n\n- R1 [auto] Visitors can read the notes\n'
    [ "${1:-}" != human ] || printf -- '- R2 [human] The notes page feels calm\n'
    printf '\n## Commands\n\n- test: sh tests/run.sh\n'
  } > .vbw/spec.md
  printf 'sh tests/notes.sh\n' > tests/run.sh
  # The proof runs on a clean copy of HEAD: the project command must be committed.
  git add tests/run.sh
  git commit -q -m "test(run): the project test command"
  printf 'grep -qx notes src/notes.txt\n' > tests/notes.sh
  "$VBW" spec sync > /dev/null
  local reqs='["R1"]'
  [ "${1:-}" != human ] || reqs='["R1","R2"]'
  jq -nc --argjson reqs "$reqs" '{phases: [{id: "P1", title: "Notes", reqs: $reqs, goal: "Notes can be read", criteria: ["the notes show"]}],
    plans: [{id: "P1.1", phase: "P1", title: "Notes", reqs: ["R1"], files: ["src/notes.txt"], after: [], tasks: ["write the notes"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/notes.sh"], files: ["tests/notes.sh"]}],
    rules: [{req: "R1", text: "the notes show", check: "C1"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'notes\n' > src/notes.txt
  "$VBW" commit P1.1 "feat(notes): notes" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null
  if [ "${1:-}" = human ]; then
    "$VBW" qa record P1 pass quick > /dev/null
    "$VBW" req skip R2 > /dev/null
  fi
  "$VBW" ship > /dev/null
  # The figure comes before M2 opens, so M2's baseline holds s1 at $2.00.
  figures s1 2 1000 100
  "$VBW" milestone start "Next" > /dev/null
  "$VBW" todo add "Visitors can read a greeting" > /dev/null
  "$VBW" todo add "Visitors can read a farewell" > /dev/null
}

# loop_started ARGS...: a loop_project with the loop started by session s1 as
# vbw loop start ARGS... (items and a ceiling choice). A later stage of the
# fixture, built once per file with fixture_build NAME loop_started ARGS...
loop_started() {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start "$@" > /dev/null
}

# loop_next [SESSION]: the kernel's loop step, as that session (s1 by default).
loop_next() { VBW_SESSION_ID="${1:-s1}" "$VBW" loop next --json < /dev/null; }

# next_action [SESSION]: what vbw next answers, as that session.
next_action() { VBW_SESSION_ID="${1:-s1}" "$VBW" next --json < /dev/null | jq -r .action; }

# item_req ITEM: the id of the requirement whose text is the item's, in the current milestone.
item_req() {
  jq -r --arg t "$1" '.milestone.id as $m | [.requirements[] | select(.milestone == $m and .text == $t)][0].id // ""' .vbw/record.json
}

# loop_plan REQ PHASE: the Lead's work for the item's requirement, as a test
# stands in for the planning workflow: a check (tests/greet.sh, failing until
# src/greet.txt says hello), one plan writing src/greet.txt, and its rule.
loop_plan() {
  local q=$1 p=$2 c
  c="C$(jq '[.checks[].id | ltrimstr("C") | tonumber] | max + 1' .vbw/record.json)"
  printf 'grep -qx hello src/greet.txt\n' > tests/greet.sh
  jq -nc --arg q "$q" --arg p "$p" --arg c "$c" '{phases: [{id: $p, title: "Greeting", reqs: [$q], goal: "A greeting exists", criteria: ["it says hello"]}],
    plans: [{id: ($p + ".1"), phase: $p, title: "Greeting", reqs: [$q], files: ["src/greet.txt"], after: [], tasks: ["write hello"]}],
    checks: [{id: $c, req: $q, run: ["sh", "tests/greet.sh"], files: ["tests/greet.sh"]}],
    rules: [{req: $q, text: "it says hello", check: $c}]}' | "$VBW" apply > /dev/null
}

# loop_build PHASE: the Dev's work, as a test stands in for the build workflow,
# inside a build run of session s1: src/greet.txt says hello, committed with
# the plan's trailer, the plan done, the run ended.
loop_build() {
  local p=$1
  VBW_SESSION_ID=s1 "$VBW" run start build "$p.1" > /dev/null
  printf 'hello\n' > src/greet.txt
  "$VBW" commit "$p.1" "feat(greet): hello" > /dev/null
  "$VBW" plan done "$p.1" > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
}

# loop_break PHASE: a later commit of the plan breaks its check (src/greet.txt
# says bye), so the next proof opens a fix.
loop_break() {
  printf 'bye\n' > src/greet.txt
  "$VBW" commit "$1.1" "feat(greet): bye" > /dev/null
}

# loop_prove: the proof, as session s1.
loop_prove() { VBW_SESSION_ID=s1 "$VBW" prove > /dev/null 2>&1 || true; }
