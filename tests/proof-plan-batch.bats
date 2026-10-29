#!/usr/bin/env bats
# R202 (docs/proof.md, plugin/lib/proofreuse.sh, testfiles.sh, proofcauses.sh):
# reuse planning (proofreuse_plan, testfiles_plan, proofcauses_find) and saving
# (proofreuse_save, testfiles_save, prove_stamp) read the run store and the
# record a fixed number of times per proof, not once per unit, fingerprint the
# units' definitions in a fixed number of processes, and run one git diff-tree
# per distinct recorded tree rather than one per unit. The decisions and the
# reasons are unchanged: a 50-unit fixture with every reason gives, per unit,
# exactly the reason the one reuse rule names. L1: counting stand-ins for git,
# jq, sha256sum and shasum on PATH around the measured command (vbw next --json
# plans a proof without running one).

load helper
load fixture-helper

# The two projects the tests read, built once per file (fixture_build) and copied
# for each test: five units and fifty units, each built by `build` in the project
# folder. A test that reads both has the fifty-unit copy beside the project.
setup_file() {
  fixture_build five five_project
  fixture_build fifty fifty_project
}
setup() { fixture_copy five; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

five_project() { vbw_setup; build "$PROJECT" 5; }
fifty_project() { vbw_setup; build "$PROJECT" 50; }

# fifty_beside: the fifty-unit project, a copy of the fixture, at $TEST_ROOT/fifty.
fifty_beside() {
  mkdir -p "$TEST_ROOT/fifty"
  cp -Rp "$(fixture_root fifty)/project with space/." "$TEST_ROOT/fifty/"
}

# standins: counting stand-ins for git, jq, sha256sum and shasum, counted in $COUNT_DIR.
standins() {
  local tool real
  mkdir -p "$TEST_ROOT/standin"
  for tool in git jq sha256sum shasum; do
    real=$(command -v "$tool" 2> /dev/null) || continue
    cat > "$TEST_ROOT/standin/$tool" << SH
#!/bin/sh
case " \$* " in *" diff-tree "*) printf 'x\\n' >> "\$COUNT_DIR/difftree" ;; esac
printf 'x\\n' >> "\$COUNT_DIR/$tool"
exec "$real" "\$@"
SH
    chmod +x "$TEST_ROOT/standin/$tool"
  done
  COUNT_DIR="$TEST_ROOT/counts"
  mkdir -p "$COUNT_DIR"
  export COUNT_DIR
}

# build DIR N: a project at DIR with checks C1..CN of R1, every one running
# tests/unit.sh with its number: check i lists src/di when 41 <= i <= 45, else
# reads src/fi.txt. The checks share one check file, so the contract hash (one
# SHA-256 per check file, outside this phase) costs the same for 5 and for 50.
# Approved, proved once (so the store holds every run), then one commit to a
# file no unit reads.
build() {
  local dir="$1" n="$2" i checks='[]'
  mkdir -p "$dir"
  (
    set -e
    cd "$dir"
    vbw_git_project
    "$VBW" init > /dev/null
    mkdir -p src tests
    printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
    "$VBW" spec sync > /dev/null
    cat > tests/unit.sh << 'SH'
# tests/unit.sh N: unit N lists src/dN (41 to 45) or reads src/fN.txt.
if [ "$1" -ge 41 ] && [ "$1" -le 45 ]; then ls "src/d$1" > /dev/null; else grep -q . "src/f$1.txt"; fi
SH
    for ((i = 1; i <= n; i++)); do
      mkdir -p "src/d$i"
      printf 'x\n' > "src/d$i/x.txt"
      printf '%s\n' "$i" > "src/f$i.txt"
      checks=$(printf '%s' "$checks" | jq -c --arg id "C$i" --arg n "$i" '. + [{id: $id, req: "R1", run: ["sh", "tests/unit.sh", $n], files: ["tests/unit.sh"]}]')
    done
    printf 'zzz\n' > src/zzz.txt
    jq --argjson c "$checks" '.checks = $c
      | .phases = [{id: "P1", title: "Shop", reqs: ["R1"], milestone: "M1"}]
      | .plans = [{id: "P1.1", phase: "P1", title: "Shop", reqs: ["R1"], files: ["src/zzz.txt"], after: [], status: "done"}]
      | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
      .vbw/record.json > "$TEST_ROOT/edit.json"
    cp "$TEST_ROOT/edit.json" .vbw/record.json
    git add -A && git commit -q -m "chore(vbw): plan"
    "$VBW" approve > /dev/null
    "$VBW" prove > /dev/null
    printf 'more\n' >> src/zzz.txt
    git add -A && git commit -q -m "chore: unread change"
  )
}

# counted DIR: run vbw next --json in DIR with the stand-ins first on PATH; the counts are in $COUNT_DIR.
counted() {
  standins
  rm -f "$COUNT_DIR"/*
  (cd "$1" && PATH="$TEST_ROOT/standin:$PATH" "$VBW" next --json > "$TEST_ROOT/next.json" < /dev/null)
}

count() { [ -f "$COUNT_DIR/$1" ] && wc -l < "$COUNT_DIR/$1" | tr -d ' ' || echo 0; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

store_file() { printf '%s/vbw/runs.json' "$(git rev-parse --path-format=absolute --git-common-dir)"; }
edit_store() { jq "$1" "$(store_file)" > "$TEST_ROOT/store.json" && cp "$TEST_ROOT/store.json" "$(store_file)"; }

@test "R202: planning runs one git diff-tree per distinct recorded tree: the same count for 5 units and for 50" {
  fifty_beside
  counted "$PROJECT"
  local d5 d50
  d5=$(count difftree)
  counted "$TEST_ROOT/fifty"
  d50=$(count difftree)
  [ "$d5" -gt 0 ] || { echo "no diff-tree counted; is the planning reached? $(cat "$TEST_ROOT/next.json")"; false; }
  [ "$d50" -eq "$d5" ] || { echo "git diff-tree: $d5 for 5 units, $d50 for 50"; false; }
}

@test "R202: planning parses the store and the record, and fingerprints the units, in a fixed number of processes" {
  fifty_beside
  counted "$PROJECT"
  local j5 s5 j50 s50
  j5=$(count jq)
  s5=$(($(count sha256sum) + $(count shasum)))
  counted "$TEST_ROOT/fifty"
  j50=$(count jq)
  s50=$(($(count sha256sum) + $(count shasum)))
  [ "$j5" -gt 0 ] && [ "$s5" -gt 0 ] || { echo "nothing counted: jq $j5, sha $s5"; false; }
  [ $((j50 - j5)) -le 4 ] || { echo "jq processes: $j5 for 5 units, $j50 for 50"; false; }
  [ $((s50 - s5)) -le 2 ] || { echo "sha256 processes: $s5 for 5 units, $s50 for 50"; false; }
}

@test "R202: a 50-unit fixture with every reason gives each unit exactly the reason the one reuse rule names" {
  fixture_copy fifty
  cd "$PROJECT"
  local i
  # C1-C10: a file they read changed.
  for ((i = 1; i <= 10; i++)); do printf 'more\n' >> "src/f$i.txt"; done
  # C11-C15 last failed; C16-C20 have no read list; C26-C30 read through git; C31-C35 never passed.
  edit_store '
    (.runs | to_entries | map(.key as $k | ($k | ltrimstr("check:C") | tonumber) as $i
      | if $i >= 11 and $i <= 15 then .value.status = "fail"
        elif $i >= 16 and $i <= 20 then .value.reads = null
        elif $i >= 26 and $i <= 30 then .value.git = true
        else . end)
      | map(select((.key | ltrimstr("check:C") | tonumber) as $i | ($i >= 31 and $i <= 35) | not))
      | from_entries) as $r | .runs = $r'
  # C21-C25: their approved definition changed.
  edit_record '.checks |= map(((.id | ltrimstr("C") | tonumber) as $i | if $i >= 21 and $i <= 25 then . + {timeout: 100} else . end))'
  # C36-C40: the file they read was deleted.
  for ((i = 36; i <= 40; i++)); do git rm -q "src/f$i.txt"; done
  # C41-C45: a file was added to the folder they listed.
  for ((i = 41; i <= 45; i++)); do printf 'new\n' > "src/d$i/new.txt"; done
  git add -A && git commit -q -m "feat: every reason"
  "$VBW" approve > /dev/null
  vbw_run prove
  local got expect
  got=$(jq -cS '.evidence.checks | to_entries | map({key, value: (if .value.reused then "reused" else (.value.why // "no reason") end)}) | from_entries' .vbw/record.json)
  expect=$(jq -ncS '[range(1; 51)] | map(. as $i | {key: "C\($i)", value: (
      if $i <= 10 then "src/f\($i).txt changed"
      elif $i <= 15 then "last result failed"
      elif $i <= 20 then "no read list"
      elif $i <= 25 then "definition changed"
      elif $i <= 30 then "reads the project through git"
      elif $i <= 35 then "never passed"
      elif $i <= 40 then "src/f\($i).txt deleted"
      elif $i <= 45 then "src/d\($i) listing changed"
      else "reused" end)}) | from_entries')
  [ "$got" = "$expect" ] || { echo "got:    $got"; echo "expect: $expect"; echo "$output"; false; }
}

@test "R202: a folder an older store recorded as a plain name (no fingerprint) still re-runs its unit when a file is added to it" {
  fixture_copy fifty
  cd "$PROJECT"
  edit_store '.runs |= map_values(.dirs |= map(if type == "object" then .path else . end))'
  printf 'new\n' > src/d41/new.txt
  git add -A && git commit -q -m "feat: file added to a listed folder"
  "$VBW" approve > /dev/null
  vbw_run prove
  local got
  got=$(jq -r '.evidence.checks.C41 | if .reused then "reused" else (.why // "no reason") end' .vbw/record.json)
  [ "$got" = "src/d41 listing changed" ] || { echo "got: $got"; echo "$output"; false; }
  [ "$(jq -r '.evidence.checks.C42.reused' .vbw/record.json)" = true ]
}

@test "R202: a unit whose recorded code is unknown to git runs again and says so, and the others are still judged" {
  cd "$PROJECT"
  edit_store '.runs["check:C1"].tree = "0000000000000000000000000000000000000001"'
  vbw_run prove
  [ "$(jq -r '.evidence.checks.C1.why' .vbw/record.json)" = "the code it ran on is unknown" ] || { echo "$output"; false; }
  [ "$(jq -r '.evidence.checks.C2.reused' .vbw/record.json)" = true ]
}
