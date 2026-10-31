#!/usr/bin/env bats
# R166 (docs/proof.md): a check that listed a folder runs again when the
# folder's listing changed, including a sub-folder that appeared (its first
# file was added) or vanished (its last file was deleted), and is reused when
# only the content of a file it never read changed. The listing's fingerprint
# recorded by the run is compared with the committed code; a file whose own
# folder appeared or vanished is seen through that listing, and a file added to
# or deleted from a folder no run listed runs nothing (R168): no run could see
# it. L1: real vbw prove runs on a small project; each check logs its runs to
# $RANLOG.

load helper
load fixture-helper

setup_file() {
  fixture_build shop listing_project
  fixture_build greet greet_project
}
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# listing_project: the project every test starts from, built once per file.
listing_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p a b tests
  printf 'x\n' > a/x.txt
  printf 'y\n' > b/x.txt
  # C1 lists the folder a; C2 reads b/x.txt and lists nothing.
  printf 'echo C1 >> "$RANLOG"\nls a > /dev/null\n' > tests/c1.sh
  printf 'echo C2 >> "$RANLOG"\ncat b/x.txt > /dev/null\n' > tests/c2.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R1", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["a/x.txt", "b/x.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$RANLOG"
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# ran: what really ran since the log was last emptied, sorted, one line.
ran() { sort "$RANLOG" | tr '\n' ' '; }

# line CHECK: the summary line of one check.
line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

# commit MESSAGE: commit everything that changed.
commit() { git add -A && git commit -q -m "$1"; }

# listing_ran: C1 ran because the listing of a changed, C2 was reused, and no cause ran everything.
listing_ran() {
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; return 1; }
  [[ "$(line C1)" == *"ran: a listing changed"* ]] || { echo "$output"; return 1; }
  [[ "$(line C2)" == *"reused"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"ran everything"* ]] || { echo "$output"; return 1; }
}

@test "R166: a sub-folder that appears inside a listed folder runs the check again, naming the listing, and only it" {
  mkdir -p a/sub
  printf 'g\n' > a/sub/g.txt
  commit "feat: sub"
  vbw_run prove
  listing_ran
}

@test "R166: once the check ran with the sub-folder, it is reused until the listing changes again" {
  mkdir -p a/sub
  printf 'g\n' > a/sub/g.txt
  commit "feat: sub"
  "$VBW" prove > /dev/null
  : > "$RANLOG"
  printf 'more\n' >> a/sub/g.txt
  commit "feat: more"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
  [[ "$(line C1)" == *"reused"* ]] || { echo "$output"; false; }
}

@test "R166: a sub-folder that vanishes from a listed folder (its last file deleted) runs the check again, and only it" {
  mkdir -p a/sub
  printf 'g\n' > a/sub/g.txt
  commit "feat: sub"
  "$VBW" prove > /dev/null
  : > "$RANLOG"
  git rm -q a/sub/g.txt && git commit -q -m "feat: drop sub"
  vbw_run prove
  listing_ran
}

@test "R166: a new sub-folder with several files, nested deeper, is seen through the listing once" {
  mkdir -p a/sub/deep
  printf 'g\n' > a/sub/g.txt
  printf 'h\n' > a/sub/deep/h.txt
  commit "feat: sub"
  vbw_run prove
  listing_ran
}

@test "R166: a content change to a file in the listed folder that the check never read reuses it" {
  printf 'more\n' >> a/x.txt
  commit "feat: more x"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
  [[ "$(line C1)" == *"reused"* ]] || { echo "$output"; false; }
}

@test "R166: a file added directly inside the listed folder still runs the check again, and only it" {
  printf 'y\n' > a/y.txt
  commit "feat: y"
  vbw_run prove
  listing_ran
}

# unseen_ran_nothing: no run listed the folder or read the file, so both checks are reused and no cause ran everything.
unseen_ran_nothing() {
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; return 1; }
  [[ "$(line C1)" == *"reused"* && "$(line C2)" == *"reused"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"ran everything"* ]] || { echo "$output"; return 1; }
}

@test "R168: a file added to a sub-folder that already existed, which no run listed, runs nothing: no run could see it" {
  mkdir -p a/sub
  printf 'g\n' > a/sub/g.txt
  commit "feat: sub"
  "$VBW" prove > /dev/null
  : > "$RANLOG"
  printf 'h\n' > a/sub/h.txt
  commit "feat: h"
  vbw_run prove
  unseen_ran_nothing
}

@test "R168: a file deleted from a sub-folder that keeps other files, which no run listed, runs nothing" {
  mkdir -p a/sub
  printf 'g\n' > a/sub/g.txt
  printf 'h\n' > a/sub/h.txt
  commit "feat: sub"
  # Both checks ran with the file present (a plain proof would reuse C2 from before it existed).
  "$VBW" prove --full > /dev/null
  : > "$RANLOG"
  git rm -q a/sub/h.txt && git commit -q -m "feat: drop h"
  vbw_run prove
  unseen_ran_nothing
}

# R226 (T194): a check whose test only executes a script by its path (./greet.sh) has
# no folder listing on its read list, as one that runs it through sh has none, so a
# commit that adds an unrelated file at the project root reuses it. Built once per
# file: the greet project, proved once.

# greet_project: greet.sh at the project root, run by C3 as ./greet.sh and by C4 as sh greet.sh.
greet_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '#!/bin/sh\necho hello\n' > greet.sh
  chmod +x greet.sh
  # C5 runs lister.sh by its path; the script itself lists the folder data/, which stays a read.
  mkdir data
  printf 'x\n' > data/x.txt
  printf '#!/bin/sh\nls data > /dev/null\n' > lister.sh
  chmod +x lister.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer is greeted\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  edit_record '.checks = [{id:"C3", req:"R1", run:["./greet.sh"], files:["greet.sh"]},
      {id:"C4", req:"R1", run:["sh","greet.sh"], files:["greet.sh"]},
      {id:"C5", req:"R1", run:["./lister.sh"], files:["lister.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  STORE="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  export STORE
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
}

@test "R226: a check whose test only executes a script by its path has no folder on its read list, as the one that runs it through sh has none" {
  fixture_copy greet
  jq -e '.runs["check:C3"].dirs == [] and .runs["check:C4"].dirs == [] and (.runs["check:C3"].reads | index("greet.sh") != null)' "$STORE" > /dev/null || {
    echo "read lists:"
    jq -c '.runs | map_values({reads, dirs})' "$STORE"
    false
  }
}

@test "R226: a commit that adds an unrelated file at the project root reuses the check that only executes a script by its path, and the proof names it as reused" {
  fixture_copy greet
  printf 'notes\n' > NOTES.md
  commit "docs: notes"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(line C3)" == *"reused"* && "$(line C4)" == *"reused"* ]] || { echo "$output"; false; }
  [[ "$output" != *"ran everything"* ]] || { echo "$output"; false; }
}

@test "R226: a folder the script run by its path lists itself stays on its read list, and a file added to it reruns the check" {
  fixture_copy greet
  jq -e '.runs["check:C5"].dirs | map(.path) | index("data") != null' "$STORE" > /dev/null || {
    echo "read list:"
    jq -c '.runs["check:C5"]' "$STORE"
    false
  }
  printf 'y\n' > data/y.txt
  commit "feat: another data file"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(line C5)" != *"reused"* ]] || { echo "$output"; false; }
}
