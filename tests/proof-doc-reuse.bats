#!/usr/bin/env bats
# R144 (docs/proof.md): when every file changed since the last proof whose
# project test command passed is documentation (is_doc: .md, .markdown, .rst)
# or VBW's own .vbw/ files, vbw prove --full reuses that passing test-command
# result instead of running the command, says so, and still counts as a full
# proof. Code, a test file, a file an approved check lists or runs (even a
# Markdown one), uncommitted code, changed test-command words, a failed or
# quick-only earlier result, nothing committed since the proof (D173) and an
# unfinished proof all make the test command run. Every approved check and
# every other command still runs. Each check and command logs its own name to
# $RANLOG when it really runs, so a reused result shows as a missing line. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] The shop rules are published\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests/fixtures docs
  printf 'paid\n' > src/pay.txt
  printf '# Guide\n' > docs/guide.md
  printf '# Listed by C2\n' > docs/listed.md
  printf '# Read by C2\n' > docs/rules.md
  printf 'Notes\n====\n' > docs/notes.rst
  printf '# Sample\n' > tests/fixtures/sample.md
  printf 'plain data\n' > words.txt
  cat > tests/c1.sh << 'SH'
echo "C1" >> "$RANLOG"
grep -qx paid src/pay.txt
SH
  cat > tests/c2.sh << 'SH'
echo "C2" >> "$RANLOG"
[ -f "$1" ]
SH
  # A command fails while the file $TEST_ROOT/fail-<name> exists.
  cat > tests/cmd.sh << 'SH'
echo "cmd-$1" >> "$RANLOG"
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

teardown() { vbw_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# ran: what really ran since the log was last emptied, sorted, one line.
ran() { sort "$RANLOG" | tr '\n' ' '; }

# commit_change FILE...: append a line to each file and commit them.
commit_change() {
  local f
  for f in "$@"; do printf 'more\n' >> "$f"; done
  git add -- "$@" && git commit -q -m "change: $*"
}

line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

# test_ran, test_reused: the test command really ran, or did not run, since
# the log was last emptied.
test_ran() { grep -qx 'cmd-test' "$RANLOG"; }
test_reused() { [ -z "$(grep -x 'cmd-test' "$RANLOG")" ]; }

@test "R144: after a documentation-only commit, prove --full reuses the passing test-command result, runs every check and every other command, and says so" {
  commit_change docs/guide.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 cmd-lint " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.commands.test.status == "pass" and .evidence.commands.test.reused == true' .vbw/record.json \
    || { jq '.evidence.commands' .vbw/record.json; false; }
  jq -e '.evidence.checks | all(.[]; (.reused // false) | not)' .vbw/record.json
  jq -e '(.evidence.commands.lint.reused // false) | not' .vbw/record.json
  [[ "$(line test)" == *pass* && "$(line test)" == *reused* ]] || { echo "$output"; false; }
}

@test "R144: a proof whose only reused result is the test command under this rule is full, in the summary and in the evidence" {
  commit_change docs/guide.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused
  printf '%s\n' "$output" | grep -qE '^ +proof: full$' || { echo "$output"; false; }
  jq -e '.evidence.full == true and .evidence.passed == true' .vbw/record.json
}

@test "R144: Markdown, .markdown and .rst files anywhere outside tests count as documentation" {
  printf '# Changes\n' > CHANGES.markdown
  git add CHANGES.markdown && git commit -q -m "docs: changes"
  commit_change README.md docs/notes.rst docs/guide.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused || { echo "ran: $(ran)"; false; }
}

@test "R144: VBW's own .vbw/ files, alone or with documentation, still let the test result be reused" {
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  commit_change docs/guide.md
  "$VBW" decide "Use round corners" "the owner prefers them" > /dev/null
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused || { echo "ran: $(ran)"; false; }
}

@test "R144: a committed change to a code file makes prove --full run the test command again" {
  commit_change src/pay.txt
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 cmd-lint cmd-test " ] || { echo "ran: $(ran)"; false; }
  jq -e '(.evidence.commands.test.reused // false) | not' .vbw/record.json
}

@test "R144: a code change committed before a documentation change still makes the test command run" {
  commit_change src/pay.txt
  commit_change docs/guide.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: plain text is not documentation: a changed .txt file makes the test command run" {
  commit_change words.txt
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: a changed test file makes the test command run, even when it is a Markdown file" {
  commit_change tests/fixtures/sample.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: a Markdown file an approved check lists in its files makes the test command run" {
  commit_change docs/listed.md
  "$VBW" approve > /dev/null
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: a Markdown file an approved check runs (named in its run words) makes the test command run" {
  commit_change docs/rules.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: uncommitted changes to code in the working folder make the test command run" {
  commit_change docs/guide.md
  printf 'paid\n# not committed\n' > src/pay.txt
  vbw_run prove --full
  test_ran || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R144: a change to the test command's words makes it run again" {
  edit_record '.commands.test = ["sh","tests/cmd.sh","test","--all"]'
  "$VBW" approve > /dev/null
  commit_change docs/guide.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: when the latest test-command result failed, it is never reused: the full test command runs" {
  # Nothing committed since the passing proof: this proof runs fresh (D173), and the test command fails.
  touch "$TEST_ROOT/fail-test"
  vbw_run prove --full
  [ "$status" -ne 0 ]
  test_ran
  jq -e '.evidence.commands.test.status == "fail"' .vbw/record.json
  rm -f "$TEST_ROOT/fail-test"
  : > "$RANLOG"
  commit_change docs/guide.md
  vbw_run prove --full
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

@test "R144: a second prove --full with nothing committed since the passing proof runs everything fresh (D173)" {
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 cmd-lint cmd-test " ] || { echo "ran: $(ran)"; false; }
  [[ "$output" != *reused* ]] || { echo "$output"; false; }
}

@test "R144: an unfinished earlier proof (its marker is left behind) is never reused" {
  commit_change docs/guide.md
  : > .vbw/runtime/prove.unfinished
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_ran || { echo "ran: $(ran)"; false; }
}

@test "R144: vbw qa record and vbw ship accept a full proof whose test result was reused under this rule" {
  commit_change docs/guide.md
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  test_reused
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = ship ] || { echo "$output"; false; }
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R144: vbw qa record still refuses a proof that ran only part of the checks or commands" {
  commit_change docs/guide.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]] || { echo "$output"; false; }
}
