#!/usr/bin/env bats
# R166 (docs/proof.md): while a check runs, vbw prove writes down every project
# file it opened and every folder it listed (its read list), from the run
# itself. A later proof reuses the check's pass only when its approved
# definition is unchanged, no file on its read list was changed, deleted or
# renamed, and no file was added to or removed from a folder it listed; in
# every other case the check runs again, and its summary line says why. A
# check whose last result failed, that never passed or that has no read list
# always runs. When the file system cannot record reads, nothing is reused.
# vbw prove --full reuses nothing and is a full proof; a proof that reused is
# not. Each check logs its name to $RANLOG when it really runs. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer sees the price list\n- R3 [auto] A customer can refund\n- R4 [auto] A customer can log in\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src/prices tests
  printf 'app\n' > src/app.txt
  printf 'paid\n' > src/pay.txt
  printf 'unread\n' > src/other.txt
  printf '1\n' > src/prices/a.txt
  printf 'user\n' > src/login.txt
  # C1 reads src/pay.txt, which it does not declare (the case D181 missed).
  cat > tests/c1.sh << 'SH'
echo C1 >> "$RANLOG"
grep -qx paid src/pay.txt
SH
  # C2 lists a folder without opening the files in it.
  cat > tests/c2.sh << 'SH'
echo C2 >> "$RANLOG"
ls src/prices > /dev/null
SH
  # C3 fails while $TEST_ROOT/fail3 exists (outside the project).
  cat > tests/c3.sh << 'SH'
echo "C3$1" >> "$RANLOG"
[ ! -e "$TEST_ROOT/fail3" ]
SH
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  # C5 declares no files at all; it reads src/login.txt.
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R2", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]},
      {id:"C3", req:"R3", run:["sh","tests/c3.sh"], files:["tests/c3.sh"]},
      {id:"C5", req:"R4", run:["sh","-c","echo C5 >> \"$RANLOG\"; grep -qx user src/login.txt"]}]
    | .commands = {}
    | .phases = [{id:"P1", title:"Shop", reqs:["R1","R2","R3","R4"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1","R2","R3","R4"], files:["src/app.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  FIRST=$(jq -r '.evidence.at' .vbw/record.json)
  : > "$RANLOG"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# ran: what really ran since the log was last emptied, sorted, one line.
ran() { sort "$RANLOG" | tr '\n' ' '; }

# change FILE: commit a change to one project file.
change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "feat: change $1"
}

# line ID: the proof summary line of one check.
line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

# no_reads: a stand-in touch that cannot reset access times, as on a file
# system that records no reads (VBW resets access times with touch -a).
no_reads() {
  local real
  real=$(command -v touch)
  mkdir -p "$TEST_ROOT/noreads"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -*a*) exit 0 ;; esac; done\nexec %s "$@"\n' "$real" > "$TEST_ROOT/noreads/touch"
  chmod +x "$TEST_ROOT/noreads/touch"
}

@test "R166: a check whose test reads a project file it does not declare runs again when a commit changes only that file (the case D181 missed)" {
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C1 | grep -qE 'ran: .*src/pay\.txt' || { echo "$output"; false; }
}

@test "R166: a commit that changes only a file no check read reuses every check, each naming the proof it came from" {
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  local id
  for id in C1 C2 C3 C5; do
    line "$id" | grep -qF "reused (proof of $FIRST)" || { echo "$id: $(line "$id")"; echo "$output"; false; }
  done
}

@test "R166: a check that declares no files is reused when nothing it read changed, and runs when a file it read changed" {
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [[ "$(ran)" != *C5* ]] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  change src/login.txt
  vbw_run prove
  [ "$(ran)" = "C5 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: deleting a file a check read runs that check again" {
  git rm -q src/pay.txt && git commit -q -m "feat: drop pay"
  vbw_run prove
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C1 | grep -qE 'ran: .*src/pay\.txt' || { echo "$output"; false; }
}

@test "R166: renaming a file a check read runs that check again" {
  git mv src/pay.txt src/paid.txt && git commit -q -m "feat: rename pay"
  vbw_run prove
  [[ " $(ran)" == *" C1 "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: adding a file to a folder a check listed runs that check again, and only it" {
  printf '2\n' > src/prices/b.txt
  git add src/prices/b.txt && git commit -q -m "feat: a price"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C2 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: removing a file from a folder a check listed runs that check again, and only it" {
  git rm -q src/prices/a.txt && git commit -q -m "feat: drop a price"
  vbw_run prove
  [ "$(ran)" = "C2 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a content change to a file in a listed folder that no check opened runs nothing" {
  change src/prices/a.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a changed approved definition runs that check again" {
  edit_record '(.checks[] | select(.id == "C3")).run = ["sh","tests/c3.sh","x"]'
  git commit -q -am "chore(vbw): C3 takes an argument"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C3x " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a change to a check's own test file, approved again, runs that check again" {
  printf '# edited\n' >> tests/c1.sh
  git add tests/c1.sh && git commit -q -m "test: edit c1"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a check whose last result failed runs again though nothing it read changed, and the summary says why" {
  : > "$TEST_ROOT/fail3"
  "$VBW" prove --full > /dev/null || true
  rm -f "$TEST_ROOT/fail3"
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C3 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C3 | grep -q 'ran: last result failed' || { echo "$output"; false; }
}

@test "R166: a check that never passed runs, and the summary says why" {
  printf 'echo C4 >> "$RANLOG"\n' > tests/c4.sh
  git add tests/c4.sh && git commit -q -m "test: c4"
  edit_record '.checks += [{id:"C4", req:"R3", run:["sh","tests/c4.sh"], files:["tests/c4.sh"]}]'
  git commit -q -am "chore(vbw): C4"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C4 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C4 | grep -q 'ran: never passed' || { echo "$output"; false; }
}

@test "R166: when the file system cannot record reads, the proof reuses nothing, runs every check and says so" {
  no_reads
  change src/other.txt
  PATH="$TEST_ROOT/noreads:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 C3 C5 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  [[ "$output" == *"does not record which files are read"* ]] || { echo "$output"; false; }
}

@test "R166: results saved without a read list always run again, and the summary says why" {
  no_reads
  PATH="$TEST_ROOT/noreads:$PATH" "$VBW" prove --full > /dev/null
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 C3 C5 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  local id
  for id in C1 C2 C3 C5; do
    line "$id" | grep -q 'ran: no read list' || { echo "$id: $(line "$id")"; echo "$output"; false; }
  done
}

@test "R166: a clone with no recorded runs, as after an older VBW, opens the record and runs every check" {
  git clone -q "$PROJECT" "$TEST_ROOT/clone"
  cd "$TEST_ROOT/clone"
  "$VBW" approve > /dev/null
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 C3 C5 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: vbw prove --full runs every check, reuses nothing and is recorded as full; a proof that reused results is not full" {
  change src/other.txt
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 C3 C5 " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.full == true and all(.evidence.checks[]; (.reused // false) == false)' .vbw/record.json
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
}
