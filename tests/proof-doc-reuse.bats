#!/usr/bin/env bats
# R144 (docs/proof.md, D260): a change after QA that touches only files the
# project test command did not read in its last passing run (documentation
# included) lets the next proof reuse that passing result instead of running
# the command again; QA verdicts and shipping accept that proof. What counts is
# what the command read, never the kind of file: a documentation or fixture
# file the test command read makes it run, and a code file it read does too.
# A changed command, a failed or quick-only earlier result and nothing committed
# since the proof (D173) all make it run. vbw prove --full reuses nothing.
# Checks and commands run on the committed code, so uncommitted changes make
# nothing run. Each check and command logs its own name to $RANLOG when it
# really runs, so a reused result shows as a missing line. Pinned once
# elsewhere, for every unit alike: nothing committed since the proof
# (proof-cause-tree.bats), --full (proof-quick.bats), uncommitted changes
# (proof-selective.bats). L1.

load helper
load fixture-helper

setup_file() { fixture_build shop doc_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# doc_project: the project every test starts from, built once per file.
doc_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] The shop rules are published\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests/fixtures docs
  printf 'paid\n' > src/pay.txt
  printf '# Guide\n' > docs/guide.md
  printf '# Manual\n' > docs/manual.md
  printf '# Listed by C2\n' > docs/listed.md
  printf '# Named by C2\n' > docs/rules.md
  printf 'Notes\n====\n' > docs/notes.rst
  printf '# Changes\n' > CHANGES.markdown
  printf '# Sample\n' > tests/fixtures/sample.md
  printf 'plain data\n' > words.txt
  cat > tests/c1.sh << 'SH'
echo "C1" >> "$RANLOG"
grep -qx paid src/pay.txt
SH
  # C2 opens the file it lists; it only looks whether the file its run names exists.
  cat > tests/c2.sh << 'SH'
echo "C2" >> "$RANLOG"
cat docs/listed.md > /dev/null
[ -f "$1" ]
SH
  # A command fails while the file $TEST_ROOT/fail-<name> exists. The test
  # command reads the code, a documentation file and a test fixture.
  cat > tests/cmd.sh << 'SH'
echo "cmd-$1" >> "$RANLOG"
if [ "$1" = test ]; then cat src/pay.txt docs/manual.md tests/fixtures/sample.md > /dev/null; fi
[ ! -e "$TEST_ROOT/fail-$1" ]
SH
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R2", run:["sh","tests/c2.sh","docs/rules.md"], files:["tests/c2.sh","docs/listed.md"]}]
    | .commands = {lint: ["sh","tests/cmd.sh","lint"], test: ["sh","tests/cmd.sh","test"]}
    | .phases = [{id:"P1", title:"Shop", reqs:["R1","R2"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"},
                {id:"P1.2", phase:"P1", title:"Rules", reqs:["R2"], files:["docs/rules.md"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
  jq -e '.evidence.passed == true and .evidence.full == true and .evidence.commands.test.status == "pass"' .vbw/record.json > /dev/null
  : > "$RANLOG"
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# ran: what really ran since the log was last emptied, sorted, one line.
ran() { sort "$RANLOG" | tr '\n' ' '; }

# commit_change FILE...: append a line to each file and commit them.
commit_change() {
  local f
  for f in "$@"; do printf 'more\n' >> "$f"; done
  git add -- "$@" && git commit -q -m "change: $*"
}

# line NAME: NAME's result line of the summary (never the counts line "test files: N ran").
line() { printf '%s\n' "$output" | grep -E "^ +$1 (pass|fail|timeout|skipped|waiting)( |:|$)" || true; }

# test_ran, test_reused: the test command really ran, or did not run, since
# the log was last emptied.
test_ran() { grep -qx 'cmd-test' "$RANLOG"; }
test_reused() { [ -z "$(grep -x 'cmd-test' "$RANLOG")" ]; }

@test "R144: after a commit that changes only documentation the test command did not read, vbw prove reuses its passing result, and every check and command, and says so" {
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.commands.test.status == "pass" and .evidence.commands.test.reused == true' .vbw/record.json \
    || { jq '.evidence.commands' .vbw/record.json; false; }
  [[ "$(line test)" == *pass* && "$(line test)" == *reused* ]] || { echo "$output"; false; }
  # Every proof prints both counts, the reused line names its proof, and a proof that reused is not full.
  [[ "$output" == *"checks: 0 ran, 2 reused"* ]] || { echo "$output"; false; }
  line test | grep -q 'reused (proof of ' || { echo "$output"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
}

@test "R144: a proof that reused the test result passes, and is not counted as a full proof" {
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.passed == true and .evidence.full == false' .vbw/record.json
  ! printf '%s\n' "$output" | grep -qE '^ +proof: full$' || { echo "$output"; false; }
}

@test "R144: the kind of file does not matter: Markdown, .markdown, .rst and plain text no run read all let the test result be reused" {
  commit_change README.md docs/notes.rst CHANGES.markdown words.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R144: VBW's own .vbw/ files, alone or with documentation, still let the test result be reused" {
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  commit_change docs/guide.md
  "$VBW" decide "Use round corners" "the owner prefers them" > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused || { echo "ran: $(ran)"; false; }
}

@test "R144: a committed change to a code file the test command read makes it run again, with the checks that read it" {
  commit_change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 cmd-test " ] || { echo "ran: $(ran)"; false; }
  jq -e '(.evidence.commands.test.reused // false) | not' .vbw/record.json
}

@test "R144: a code change committed before a documentation change still makes the test command run" {
  commit_change src/pay.txt
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: a documentation file the test command read makes it run, though no check lists it" {
  commit_change docs/manual.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "cmd-test " ] || { echo "ran: $(ran)"; false; }
}

@test "R144: a test file the test command read makes it run, even when it is a Markdown file" {
  commit_change tests/fixtures/sample.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "cmd-test " ] || { echo "ran: $(ran)"; false; }
}

@test "R144: a Markdown file an approved check lists and reads makes that check run, and the test command, which did not read it, is reused" {
  commit_change docs/listed.md
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C2 " ] || { echo "ran: $(ran)"; false; }
}

@test "R144: a Markdown file an approved check names in its run words but never opens makes nothing run" {
  commit_change docs/rules.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R144: a change to the test command's words makes it run again" {
  edit_record '.commands.test = ["sh","tests/cmd.sh","test","--all"]'
  "$VBW" approve > /dev/null
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: when the latest test-command result failed, it is never reused: the test command runs" {
  # Nothing committed since the passing proof: this proof runs fresh (D173), and the test command fails.
  touch "$TEST_ROOT/fail-test"
  vbw_run prove
  [ "$status" -ne 0 ]
  test_ran
  jq -e '.evidence.commands.test.status == "fail"' .vbw/record.json
  rm -f "$TEST_ROOT/fail-test"
  : > "$RANLOG"
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: a result of the quick command standing in for the test command is never reused as the test result" {
  edit_record '.commands.quick = ["sh","tests/cmd.sh","quick"]'
  "$VBW" approve > /dev/null
  commit_change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'cmd-quick' "$RANLOG"
  test_reused
  : > "$RANLOG"
  commit_change docs/guide.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
  [ -z "$(grep -x 'cmd-quick' "$RANLOG")" ]
}

@test "R144: vbw qa record and vbw ship accept a proof whose test result was reused" {
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = ship ] || { echo "$output"; false; }
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R144: vbw qa record still refuses a proof in which the quick command stood in for the test command" {
  edit_record '.commands.quick = ["sh","tests/cmd.sh","quick"]'
  "$VBW" approve > /dev/null
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]] || { echo "$output"; false; }
}
