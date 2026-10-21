#!/usr/bin/env bats
# R149: every vbw command that reads or writes the record works the same on a
# record larger than the operating system's command-line limit (more than
# 2 MB, larger than macOS's 1 MB ARG_MAX, with history lists and single
# fields larger than Linux's 128 KB per-argument limit) as on an equivalent
# small record: the same exit code and the same output, step by step through
# a whole milestone, and never "Argument list too long". Every step is also a
# clean step (big-record-scratch.bats states the rule): TMPDIR, an empty
# folder of the test, stays empty, and neither twin keeps a scratch file. The
# twins, the comparison and clean_step are in big-record-helper.bash. The
# twins are built once per file (setup_file), and so is the milestone planned,
# built and proven in both (twin_build, every step checked as above); each
# test works on its own copy. L1.

load helper
load big-record-helper
load fixture-helper

# twin_plan: the active milestone planned and approved in both twins.
twin_plan() {
  twin_doc > "$TEST_ROOT/doc.json"
  TWIN_IN="$TEST_ROOT/doc.json" clean_step apply
  clean_step approve
}

# twin_build: the active milestone planned, built, committed and proven.
twin_build() {
  twin_plan
  clean_step run start build P51.1 P52.1
  in_twins sh -c 'printf "a\n" > src/a.txt'
  clean_step commit P51.1 "feat(p51): part a"
  clean_step plan "done" P51.1
  clean_step plan block P52.1 "waiting for part a"
  clean_step plan reset P52.1
  in_twins sh -c 'printf "b\n" > src/b.txt'
  clean_step commit P52.1 "feat(p52): part b"
  clean_step plan "done" P52.1
  clean_step run confirm P51.1 P52.1
  clean_step run end
  clean_step prove
}

# built_twins: the twins, then twin_build (the fixture "built").
built_twins() {
  twin_fixture
  twin_tmpdir twin_build
}

setup_file() {
  fixture_build twins twin_fixture
  fixture_build built built_twins
}
setup() { twin_copy twins; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

@test "R149: the reading commands and every show view answer the same on a record over 2 MB" {
  clean_step status
  clean_step status --json
  clean_step next
  clean_step next --json
  clean_step spec check
  clean_step triage --json
  clean_step todo list
  clean_step config
  clean_step interview --json
  clean_step show roadmap
  clean_step show decisions
  clean_step show requirements
  clean_step show req R1
  clean_step show phase P1
  clean_step show plan P1.1
  clean_step show contract
  clean_step show evidence
}

@test "R149: spec sync, spec add, apply, apply --patch and approve work the same on a record over 2 MB" {
  clean_step spec sync
  twin_plan
  clean_step show contract
  jq -nc '{plans: [{id: "P51.1", phase: "P51", title: "Write part a", reqs: ["R51"], files: ["src/a.txt"], after: [], role: "dev", tasks: ["write a", "check a", "note a"]}]}' > "$TEST_ROOT/patch.json"
  TWIN_IN="$TEST_ROOT/patch.json" clean_step apply --patch
  clean_step show contract --changes
  clean_step approve
  clean_step next --json
  clean_step show phase P51
  clean_step show plan P51.1
  clean_step spec add auto "Part c works"
  clean_step spec check
  clean_step next --json
  clean_step show requirements
}

@test "R149: a whole build, check, prove and prove --full work the same on a record over 2 MB" {
  twin_copy built
  # The proof results alone are larger than Linux's 128 KB per-argument limit.
  jq -e '.evidence | tojson | length > 131072' "$BIG/.vbw/record.json" > /dev/null
  clean_step check
  clean_step check C101
  clean_step check C101 C102
  clean_step prove --full
  clean_step show evidence
  clean_step show phase P51
  clean_step show req R51
  clean_step status
  clean_step next --json
}

@test "R149: QA findings and verdicts, tier raise, fixes and the user's verdicts work the same on a record over 2 MB" {
  twin_copy built
  clean_step tier raise P1 deep "the user asked for a deep review"
  clean_step show phase P1
  clean_step qa record P51 pass deep
  clean_step qa finding R52 "src/b.txt is missing its last line"
  clean_step qa record P52 fail deep "one finding"
  clean_step show fix F1
  clean_step next --json
  clean_step run start fix F1
  in_twins sh -c 'printf "b\nb\n" > src/b.txt'
  clean_step commit P52.1 "fix(p52): part b"
  clean_step fix "done" F1
  clean_step run end
  clean_step req reject R53 "the pages feel busy"
  clean_step req accept R53
  clean_step show req R53
  clean_step status
  clean_step next --json
}

@test "R149: decisions, the backlog and the recommendation work the same on a record over 2 MB" {
  clean_step decide "Keep the history" "the owner wants it"
  clean_step todo add "Gift cards"
  clean_step todo add --sort next --size small "CSV export"
  clean_step todo sort T31 later large
  clean_step todo "done" T31
  clean_step todo drop T32
  clean_step todo list
  jq -nc '{top: {text: "Refunds", reason: "Customers ask for it.", size: "medium"}, runners: []}' > "$TEST_ROOT/rec.json"
  TWIN_IN="$TEST_ROOT/rec.json" clean_step recommend
  clean_step status
  clean_step show decisions
}
