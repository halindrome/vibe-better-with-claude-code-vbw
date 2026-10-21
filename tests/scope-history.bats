#!/usr/bin/env bats
# R204 (docs/proof.md, scope): the scope check's cost does not grow in the
# shell with the history. git lists the history once and jq sorts it out; the
# shell runs the same commands for 50 plan commits as for 500 (no loop over
# commits or their files, whose string matching grew with the square of the
# history: 108 s on a 7,653-commit history), and the result is unchanged. L1:
# prove_scope on a fixture project, its shell commands counted from bash's
# trace (xtrace), no clock.

load helper

KEEP_PROTECTED='if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:.milestone.id}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt", "src/more/"], after:[], status:"done"}]' \
    .vbw/record.json > "$TEST_ROOT/edit.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/edit.json" > .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
}

teardown() { vbw_teardown; }

# history DIR N: N commits of P1.1 in DIR, each changing two of its files, through one git fast-import.
history() {
  (
    cd "$1" || exit 1
    local i
    {
      for ((i = 1; i <= $2; i++)); do
        printf 'commit refs/heads/main\ncommitter Test <test@example.com> %s +0000\n' "$((1700000000 + i))"
        printf 'data <<EOM\nfeat(pay): change %s\n\nVBW-Plan: P1.1\nEOM\n' "$i"
        [ "$i" -gt 1 ] || printf 'from %s\n' "$(git rev-parse HEAD)"
        printf 'M 100644 inline src/pay.txt\ndata <<EOM\npaid\n# change %s\nEOM\n' "$i"
        printf 'M 100644 inline src/more/note-%s.txt\ndata <<EOM\nnote %s\nEOM\n\n' "$((i % 7))" "$i"
      done
    } | git fast-import --quiet --force
    git checkout -q -f main 2> /dev/null || git reset -q --hard main
    [ "$(git log --format='%(trailers:key=VBW-Plan,valueonly)' | grep -c '^P1.1$')" -eq "$2" ]
  )
}

# scope_trace DIR: runs prove_scope in DIR with bash's trace on; prints its result
# and leaves the number of traced shell commands in $TEST_ROOT/count.
scope_trace() {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  (cd "$1" && vbw_kernel '. "$VBW_LIB/cmd-prove.sh"; r=$(cat "$VBW_RECORD"); PS4="+ "; set -x
    prove_scope "$r" 2> "$TEST_ROOT/trace"; set +x') 2> /dev/null
  grep -c '^+' "$TEST_ROOT/trace" > "$TEST_ROOT/count"
}

@test "R204: the scope check runs the same shell commands for 500 plan commits as for 50, with the same result" {
  local small big
  git branch -M main
  cp -R "$PROJECT" "$TEST_ROOT/big"
  history "$PROJECT" 50
  history "$TEST_ROOT/big" 500
  small=$(scope_trace "$PROJECT")
  local n50 n500
  n50=$(cat "$TEST_ROOT/count")
  big=$(scope_trace "$TEST_ROOT/big")
  n500=$(cat "$TEST_ROOT/count")
  [ "$small" = '{"scope":[],"undone":[]}' ] || { echo "50: $small"; false; }
  [ "$big" = '{"scope":[],"undone":[]}' ] || { echo "500: $big"; false; }
  [ "$n50" -gt 0 ] || { echo "no traced command"; false; }
  [ "$n500" -eq "$n50" ] || { echo "shell commands: $n50 for 50 commits, $n500 for 500"; false; }
}
