#!/usr/bin/env bats
# R149: every vbw command that reads or writes the record works the same on a
# record larger than the operating system's command-line limit (more than
# 2 MB, larger than macOS's 1 MB ARG_MAX, with history lists and single
# fields larger than Linux's 128 KB per-argument limit) as on an equivalent
# small record: the same exit code and the same output, step by step through
# a whole milestone, and never "Argument list too long". The twins and the
# comparison are in big-record-helper.bash. L1.

load helper
load big-record-helper

setup() {
  vbw_setup
  twins
}

teardown() { vbw_teardown; }

# twin_plan: the active milestone planned and approved in both twins.
twin_plan() {
  twin_doc > "$TEST_ROOT/doc.json"
  TWIN_IN="$TEST_ROOT/doc.json" twin_step apply
  twin_step approve
}

# twin_build: the active milestone planned, built, committed and proven.
twin_build() {
  twin_plan
  twin_step run start build P51.1 P52.1
  in_twins sh -c 'printf "a\n" > src/a.txt'
  twin_step commit P51.1 "feat(p51): part a"
  twin_step plan "done" P51.1
  twin_step plan block P52.1 "waiting for part a"
  twin_step plan reset P52.1
  in_twins sh -c 'printf "b\n" > src/b.txt'
  twin_step commit P52.1 "feat(p52): part b"
  twin_step plan "done" P52.1
  twin_step run confirm P51.1 P52.1
  twin_step run end
  twin_step prove
}

@test "R149: the reading commands and every show view answer the same on a record over 2 MB" {
  twin_step status
  twin_step status --json
  twin_step next
  twin_step next --json
  twin_step spec check
  twin_step triage --json
  twin_step todo list
  twin_step config
  twin_step interview --json
  twin_step show roadmap
  twin_step show decisions
  twin_step show requirements
  twin_step show req R1
  twin_step show phase P1
  twin_step show plan P1.1
  twin_step show contract
  twin_step show evidence
}

@test "R149: spec sync, spec add, apply, apply --patch and approve work the same on a record over 2 MB" {
  twin_step spec sync
  twin_plan
  twin_step show contract
  jq -nc '{plans: [{id: "P51.1", phase: "P51", title: "Write part a", reqs: ["R51"], files: ["src/a.txt"], after: [], role: "dev", tasks: ["write a", "check a", "note a"]}]}' > "$TEST_ROOT/patch.json"
  TWIN_IN="$TEST_ROOT/patch.json" twin_step apply --patch
  twin_step show contract --changes
  twin_step approve
  twin_step next --json
  twin_step show phase P51
  twin_step show plan P51.1
  twin_step spec add auto "Part c works"
  twin_step spec check
  twin_step next --json
  twin_step show requirements
}

@test "R149: a whole build, check, prove and prove --full work the same on a record over 2 MB" {
  twin_build
  # The proof results alone are larger than Linux's 128 KB per-argument limit.
  jq -e '.evidence | tojson | length > 131072' "$BIG/.vbw/record.json" > /dev/null
  twin_step check
  twin_step check C101 C102
  twin_step prove --full
  twin_step show evidence
  twin_step show phase P51
  twin_step show req R51
  twin_step status
  twin_step next --json
}

@test "R149: QA findings and verdicts, tier raise, fixes and the user's verdicts work the same on a record over 2 MB" {
  twin_build
  twin_step tier raise P1 deep "the user asked for a deep review"
  twin_step show phase P1
  twin_step qa record P51 pass deep
  twin_step qa finding R52 "src/b.txt is missing its last line"
  twin_step qa record P52 fail deep "one finding"
  twin_step show fix F1
  twin_step next --json
  twin_step run start fix F1
  in_twins sh -c 'printf "b\nb\n" > src/b.txt'
  twin_step commit P52.1 "fix(p52): part b"
  twin_step fix "done" F1
  twin_step run end
  twin_step req reject R53 "the pages feel busy"
  twin_step req accept R53
  twin_step show req R53
  twin_step status
  twin_step next --json
}

@test "R149: decisions, the backlog and the recommendation work the same on a record over 2 MB" {
  twin_step decide "Keep the history" "the owner wants it"
  twin_step todo add "Gift cards"
  twin_step todo add --sort next --size small "CSV export"
  twin_step todo sort T31 later large
  twin_step todo "done" T31
  twin_step todo drop T32
  twin_step todo list
  jq -nc '{top: {text: "Refunds", reason: "Customers ask for it.", size: "medium"}, runners: []}' > "$TEST_ROOT/rec.json"
  TWIN_IN="$TEST_ROOT/rec.json" twin_step recommend
  twin_step status
  twin_step show decisions
}
