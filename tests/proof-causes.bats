#!/usr/bin/env bats
# R168 (docs/proof.md): when VBW cannot know what a change affects, vbw prove
# runs every check and every test file and names the cause in plain words: a
# file was added or deleted that no recorded run read and no recorded run
# listed the folder of; the file system cannot record reads; this clone has no
# earlier recorded run; the last proof was cut short. A changed approved
# command, single-file form or list of test files re-runs only what runs
# through it (each unit by its own definition), and a file every test file
# reads re-runs those files and nothing else. A content change to a file no
# recorded run read makes nothing run. Every summary, full or not, prints
# "checks: N ran, M reused" and "test files: N ran, M reused"; one cause is
# one "ran everything:" line, several are listed one per line. Scripts log
# their runs to $RANLOG. L1.

load helper
load fixture-helper

setup_file() { fixture_build shop causes_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# causes_project: the project every test starts from, built once per file.
causes_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'c\n' > src/c.txt
  printf 'unread\n' > src/unread.txt
  printf 'ready=1\n' > tests/helper.sh
  printf 'echo t_a >> "$RANLOG"\n. tests/helper.sh\ngrep -q . src/a.txt\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\n. tests/helper.sh\n' > tests/t_b.sh
  printf 'echo C1 >> "$RANLOG"\ngrep -q . src/c.txt\n' > tests/c1.sh
  printf 'echo "lint$1" >> "$RANLOG"\n' > tests/lint.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  spec 'sh tests/lint.sh' 'sh {file}' 'tests/t_*.sh' > /dev/null
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/a.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$RANLOG"
}

# spec LINT RUN FILES: the spec with the lint command, the test command and the
# single-file form RUN over FILES; then sync it.
spec() {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n- lint: %s\n\n## Test files\n\n- run: %s\n- files: %s\n' "$1" "$2" "$3" > .vbw/spec.md
  "$VBW" spec sync
}

# respec LINT RUN FILES: change the spec, commit it and approve it again.
respec() {
  spec "$@" > /dev/null
  git add -A && git commit -q -m "chore(vbw): commands"
  "$VBW" approve > /dev/null
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "feat: change $1"
}

# everything: every check and every test file ran.
everything() {
  [[ " $(ran)" == *" C1 "* && " $(ran)" == *" t_a "* && " $(ran)" == *" t_b "* ]] || { echo "ran: $(ran)"; echo "$output"; return 1; }
}

# cause TEXT: the summary gives TEXT as the one reason everything ran.
cause() {
  printf '%s\n' "$output" | grep -qE "^ +ran everything: .*$1" || { echo "no single cause matching: $1"; echo "$output"; return 1; }
}

no_reads() {
  local real
  real=$(command -v touch)
  mkdir -p "$TEST_ROOT/noreads"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -*a*) exit 0 ;; esac; done\nexec %s "$@"\n' "$real" > "$TEST_ROOT/noreads/touch"
  chmod +x "$TEST_ROOT/noreads/touch"
}

# nothing_global: the summary has no "ran everything" line.
nothing_global() { ! printf '%s\n' "$output" | grep -q 'ran everything' || { echo "$output"; return 1; }; }

@test "R168: a changed approved command re-runs that command only, and its line says why" {
  respec 'sh tests/lint.sh x' 'sh {file}' 'tests/t_*.sh'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "lintx " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +lint pass .*ran: definition changed' || { echo "$output"; false; }
  nothing_global
}

@test "R168: a changed single-file form re-runs every test file and nothing else" {
  respec 'sh tests/lint.sh' 'sh -e {file}' 'tests/t_*.sh'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_a t_b " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +tests/t_a\.sh pass .*ran: definition changed' || { echo "$output"; false; }
  nothing_global
}

@test "R168: a changed list of test files runs the files it adds and nothing else" {
  printf 'echo u_c >> "$RANLOG"\n' > tests/u_c.sh
  git add tests/u_c.sh && git commit -q -m "feat: test u_c"
  respec 'sh tests/lint.sh' 'sh {file}' 'tests/t_*.sh tests/u_*.sh'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "u_c " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  nothing_global
}

@test "R168: a change to a file every test file reads re-runs those files and nothing else, and each line names the file" {
  change tests/helper.sh
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_a t_b " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +tests/t_a\.sh pass .*ran: tests/helper\.sh changed' || { echo "$output"; false; }
  nothing_global
}

@test "R168: an added file that no recorded run read and no recorded run listed the folder of runs everything, and names it" {
  printf 'new\n' > src/new.txt
  git add src/new.txt && git commit -q -m "feat: new"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  everything
  cause 'src/new\.txt was added'
}

@test "R168: a deleted file that no recorded run read and no recorded run listed the folder of runs everything, and names it" {
  git rm -q src/unread.txt && git commit -q -m "feat: drop unread"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  everything
  cause 'src/unread\.txt was deleted'
}

@test "R168: a content change to a file no recorded run read runs nothing" {
  change src/unread.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q 'ran everything' || { echo "$output"; false; }
}

@test "R168: when the file system cannot record reads, everything runs and the summary says so" {
  no_reads
  change src/unread.txt
  PATH="$TEST_ROOT/noreads:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  everything
  cause 'does not record which files are read'
  printf '%s\n' "$output" | grep -qxF '  ran everything: this file system does not record which files are read' || { echo "$output"; false; }
  jq -e 'all(.runs[]; .reads == null)' "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  jq -e '.evidence.full == true' .vbw/record.json
}

@test "R168: a clone with no earlier recorded run runs everything and says so" {
  git clone -q "$PROJECT" "$TEST_ROOT/clone"
  cd "$TEST_ROOT/clone"
  "$VBW" approve > /dev/null
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  everything
  cause 'no earlier recorded run'
}

@test "R168: several causes at once are each listed" {
  no_reads
  git clone -q "$PROJECT" "$TEST_ROOT/clone"
  cd "$TEST_ROOT/clone"
  "$VBW" approve > /dev/null
  PATH="$TEST_ROOT/noreads:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  everything
  printf '%s\n' "$output" | grep -qE '^ +ran everything, because:$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +- .*no earlier recorded run' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +- .*does not record which files are read' || { echo "$output"; false; }
}

@test "R168: a proof that was cut short reuses nothing the next time, and the summary says so" {
  : > .vbw/runtime/prove.unfinished
  change src/unread.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  everything
  cause 'last proof was cut short'
  # The project commands ran too, and the proof that follows reuses again.
  [[ " $(ran)" == *" lint "* ]] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R168: every summary, full or not, counts the checks and the test files that ran and were reused, and each reused result names its proof" {
  local first
  first=$(jq -r '.evidence.at' .vbw/record.json)
  change src/a.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +checks: 0 ran, 1 reused$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +test files: 1 ran, 1 reused$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E '^ +C1 ' | grep -qF "reused (proof of $first)" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E '^ +tests/t_b\.sh ' | grep -qF "reused (proof of $first)" || { echo "$output"; false; }
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +checks: 1 ran, 0 reused$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +test files: 2 ran, 0 reused$' || { echo "$output"; false; }
}
