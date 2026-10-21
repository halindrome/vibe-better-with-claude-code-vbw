#!/usr/bin/env bats
# R166 (docs/proof.md): read lists are recorded while checks still run several
# at a time (up to check_jobs), never one by one. A check that reads a file an
# earlier run of the same proof wrote (build output, a cache) depends on what
# that run read. Checks are independent: run together, each runs in its own
# slot copy and never sees another's output, so that rule applies to runs that
# follow one another in one copy (reads.sh keeps written files' lists per
# slot), shown with check_jobs 1. A check that reads the project through git (git show, git
# ls-files, ...) has reads VBW cannot see, so it always runs. Each check logs
# its name to $RANLOG when it really runs. L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] Two checks meet\n- R2 [auto] A report is built\n- R3 [auto] History is shown\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'app\n' > src/app.txt
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'unread\n' > src/other.txt
  # meet.sh ME OTHER: mark ME started, then wait (up to 20 s) for OTHER: it
  # passes only when both checks run at the same time (or when $SYNC/off exists,
  # for the tests that run one check at a time).
  cat > tests/meet.sh << 'SH'
echo "meet-$1" >> "$RANLOG"
[ ! -e "$SYNC/off" ] || exit 0
: > "$SYNC/$1"
i=0
while [ ! -e "$SYNC/$2" ]; do
  i=$((i + 1))
  [ "$i" -lt 200 ] || exit 1
  sleep 0.1
done
SH
  # C3 builds gen/out.txt from src/a.txt; C4 reads only what C3 built. Run
  # together (no $SYNC/off) C4 is in another copy and has no gen/out.txt, so
  # it then passes without depending on C3.
  cat > tests/build.sh << 'SH'
echo C3 >> "$RANLOG"
mkdir -p gen
cat src/a.txt > gen/out.txt
SH
  cat > tests/report.sh << 'SH'
echo C4 >> "$RANLOG"
[ -e "$SYNC/off" ] || exit 0
grep -q . gen/out.txt
SH
  # C5 reads committed content through git, never opening the file itself.
  cat > tests/history.sh << 'SH'
echo C5 >> "$RANLOG"
git show HEAD:src/b.txt > /dev/null
SH
  export RANLOG="$TEST_ROOT/ran.log" SYNC="$TEST_ROOT/sync"
  : > "$RANLOG"
  mkdir -p "$SYNC"
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/meet.sh","a","b"], files:["tests/meet.sh"]},
      {id:"C2", req:"R1", run:["sh","tests/meet.sh","b","a"], files:["tests/meet.sh"]},
      {id:"C3", req:"R2", run:["sh","tests/build.sh"], files:["tests/build.sh"]},
      {id:"C4", req:"R2", run:["sh","tests/report.sh"], files:["tests/report.sh"]},
      {id:"C5", req:"R3", run:["sh","tests/history.sh"], files:["tests/history.sh"]}]
    | .commands = {}
    | .phases = [{id:"P1", title:"Shop", reqs:["R1","R2","R3"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1","R2","R3"], files:["src/app.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "feat: change $1"
}

line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

# first_proof JOBS: the first proof with check_jobs JOBS, then an empty log.
first_proof() {
  "$VBW" config set check_jobs "$1" > /dev/null
  [ "$1" -gt 1 ] || : > "$SYNC/off"
  run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "the first proof failed: $output"; return 1; }
  : > "$RANLOG"
}

@test "R166: checks that must run at the same time still do while their read lists are recorded" {
  first_proof 2
  change src/other.txt
  rm -f "$SYNC"/*
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(ran)" == *"meet-a meet-b"* ]] || { echo "ran: $(ran)"; false; }
  # The first proof recorded read lists: the next one reuses what nothing changed.
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(ran)" != *meet-* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a check that reads a file an earlier run of the same proof wrote runs again when what that run read changes" {
  first_proof 1
  change src/a.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ " $(ran)" == *" C3 "* && " $(ran)" == *" C4 "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a check that reads the project through git always runs, and the summary says why" {
  first_proof 1
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ " $(ran)" == *" C5 "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
  [[ " $(ran)" != *" C3 "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C5 | grep -qE 'ran: .*git' || { echo "$output"; false; }
}
