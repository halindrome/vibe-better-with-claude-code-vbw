#!/usr/bin/env bats
# R93, R152 (docs/proof.md): the time of the stale-link scan, measured in the
# release run (tests/timed-*.bats), never in vbw prove: on a working folder with
# 50,000 files it adds under 30 s. Fixture as in tests/proof-stale-links.bats.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'node_modules/\ntarget/\n.vbw/runtime/\n' > .gitignore
  mkdir -p node_modules/@kit node_modules/pkg target
  printf 'dep\n' > node_modules/pkg/index.txt
  OUTSIDE="$TEST_ROOT/outside"
  mkdir -p "$OUTSIDE/inner"
  export OUTSIDE
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A > /dev/null
  git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

# plant: a stale absolute and a stale relative link, as an earlier VBW's proof copy left them.
plant() {
  ln -s "$PROJECT/.vbw/runtime/proof.OLDabs1/tree/packages/ui" node_modules/@kit/ui
  ln -s ../.vbw/runtime/proof.OLDrel2/tree/packages/core node_modules/core
}

@test "R93: on a working folder with 50,000 files the stale-link scan adds under 30 s" {
  local d i t0 t1 t2
  for d in $(seq 1 50); do
    mkdir -p "target/d$d"
    (cd "target/d$d" && seq 1 1000 | sed 's/^/f/' | xargs touch)
  done
  [ "$(find target -type f | wc -l | tr -d ' ')" -eq 50000 ]
  now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
  t0=$(now)
  vbw_run prove
  t1=$(now)
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  plant
  vbw_run prove
  t2=$(now)
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"proof.OLDabs1"* ]]
  i=$(perl -e 'printf "%.2f", $ARGV[0] - $ARGV[1]' "$t2" "$t1")
  echo "50,000 files in the working folder: proof without a stale link $(perl -e 'printf "%.2f", $ARGV[0] - $ARGV[1]' "$t1" "$t0") s, with one $i s" >&3
  perl -e 'exit($ARGV[0] < 30 ? 0 : 1)' "$i"
}
