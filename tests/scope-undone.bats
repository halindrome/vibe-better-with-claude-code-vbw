#!/usr/bin/env bats
# R204 (docs/proof.md, scope): the proof's scope check does not judge a commit
# that a later standing commit on the branch exactly undoes, whoever made it
# and whatever its message says. Exact means git's own view, file by file: the
# same set of paths, and for each path the later commit takes it from the
# earlier one's new (mode, blob) back to its old (mode, blob). A partial or
# edited undo is still judged. The undoing commit is not judged either when it
# carries a trailer of its own; an undo that is itself undone clears nothing.
# The evidence lists each cleared commit in evidence.undone ({commit, plan, by})
# and the summary prints one line per entry after its scope line. The walk
# costs a fixed number of git processes however long the history is. L1: the
# kernel on a fixture project.

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
  # Files outside the plan, for the edited and mode-only cases: ten lines, and a script without the executable bit.
  printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n' > src/notes.txt
  printf 'echo tool\n' > src/tool.sh
  chmod 644 src/tool.sh
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .shipped = [{id:"M0", title:"Old", at:"2026-01-01T00:00:00Z"}]
    | .phases = [{id:"P0", title:"Old", reqs:["R1"], milestone:"M0"},
                 {id:"P1", title:"Pay", reqs:["R1"], milestone:.milestone.id}]
    | .plans = [{id:"P0.1", phase:"P0", title:"Old", reqs:["R1"], files:["src/old.txt"], after:[], status:"done"},
                {id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/edit.json" > .vbw/record.json
}

# plan_commit MSG [PLAN]: commits what is staged with a VBW-Plan trailer naming PLAN (P1.1 by default); prints the full hash.
plan_commit() {
  git commit -q -m "$1" -m "VBW-Plan: ${2:-P1.1}"
  git rev-parse HEAD
}

# stray N: a commit of the current plan adding src/strayN.txt, a file outside the plan; prints the full hash.
stray() {
  printf 'stray %s\n' "$1" > "src/stray$1.txt"
  git add "src/stray$1.txt"
  plan_commit "feat(stray): stray $1"
}

# line_entry COMMIT BY: the summary line the proof prints for a cleared commit, with 12-character ids.
line_entry() { printf '  scope: %s (P1.1) undone by %s, not judged' "${1:0:12}" "${2:0:12}"; }

# undone_is JSON: evidence.undone equals the array given, in order.
undone_is() {
  jq -e --argjson want "$1" '.evidence.undone == $want' .vbw/record.json \
    || { echo "undone: $(jq -c '.evidence.undone' .vbw/record.json)"; echo "want:   $1"; return 1; }
}

# after_scope_ok LINE: the summary prints LINE after its scope ok line.
after_scope_ok() {
  local ok at
  ok=$(printf '%s\n' "$output" | grep -nF '  scope ok' | head -n 1 | cut -d: -f1)
  at=$(printf '%s\n' "$output" | grep -nF -- "$1" | head -n 1 | cut -d: -f1)
  [ -n "$ok" ] && [ -n "$at" ] && [ "$at" -gt "$ok" ] || { echo "scope ok at line ${ok:-none}, '$1' at line ${at:-none}"; echo "$output"; return 1; }
}

@test "R204: five commits outside their plan, each reverted by hand newest first, leave the proof passing, with five undone entries and five summary lines" {
  local i a=() r=() want='[]'
  for i in 1 2 3 4 5; do a[i]=$(stray "$i"); done
  for i in 5 4 3 2 1; do
    git revert --no-edit "${a[i]}" > /dev/null
    r[i]=$(git rev-parse HEAD)
  done
  for i in 5 4 3 2 1; do
    want=$(printf '%s' "$want" | jq -c --arg c "${a[i]}" --arg b "${r[i]}" '. + [{commit: $c, plan: "P1.1", by: $b}]')
  done
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope ok"* ]] || { echo "$output"; false; }
  jq -e '.evidence.passed and .evidence.scope == [] and (.evidence.undone | length) == 5
    and all(.evidence.undone[]; (.commit | test("^[0-9a-f]{40}$")) and (.by | test("^[0-9a-f]{40}$")) and .plan == "P1.1")' .vbw/record.json \
    || { jq '.evidence | {passed, scope, undone}' .vbw/record.json; false; }
  undone_is "$want"
  for i in 1 2 3 4 5; do
    [[ "$output" == *"$(line_entry "${a[i]}" "${r[i]}")"* ]] || { echo "no line for ${a[i]:0:12}"; echo "$output"; false; }
    after_scope_ok "$(line_entry "${a[i]}" "${r[i]}")"
  done
  [ "$(printf '%s\n' "$output" | grep -c 'undone by')" -eq 5 ] || { echo "$output"; false; }
}

@test "R204: an undo made as a plain commit by another author, without any revert line, clears the commit the same way" {
  local i a=() r=()
  for i in 1 2 3; do a[i]=$(stray "$i"); done
  for i in 3 2 1; do
    git rm -q "src/stray$i.txt"
    git -c user.name=Someone -c user.email=someone@example.org commit -q -m "chore(stray): take stray $i out again"
    r[i]=$(git rev-parse HEAD)
  done
  if git log --format=%B | grep -q 'This reverts commit'; then echo "a revert line is present"; false; fi
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope ok"* ]] || { echo "$output"; false; }
  undone_is "$(jq -nc --arg a1 "${a[1]}" --arg a2 "${a[2]}" --arg a3 "${a[3]}" --arg r1 "${r[1]}" --arg r2 "${r[2]}" --arg r3 "${r[3]}" \
    '[{commit: $a3, plan: "P1.1", by: $r3}, {commit: $a2, plan: "P1.1", by: $r2}, {commit: $a1, plan: "P1.1", by: $r1}]')"
  for i in 1 2 3; do [[ "$output" == *"$(line_entry "${a[i]}" "${r[i]}")"* ]] || { echo "$output"; false; }; done
}

@test "R204: a change to a file outside the plan, written back by hand to the exact same content, is cleared" {
  local a r
  sed -i.bak '1s/.*/ONE/' src/notes.txt && rm -f src/notes.txt.bak
  git add src/notes.txt
  a=$(plan_commit "feat(notes): shout the first line")
  sed -i.bak '1s/.*/one/' src/notes.txt && rm -f src/notes.txt.bak
  git add src/notes.txt
  git commit -q -m "chore(notes): first line as it was"
  r=$(git rev-parse HEAD)
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope ok"* ]] || { echo "$output"; false; }
  undone_is "$(jq -nc --arg a "$a" --arg r "$r" '[{commit: $a, plan: "P1.1", by: $r}]')"
  [[ "$output" == *"$(line_entry "$a" "$r")"* ]] || { echo "$output"; false; }
}

@test "R204: an undo with one extra line is not exact: the commit is judged and the violation names the file" {
  local a
  sed -i.bak '1s/.*/ONE/' src/notes.txt && rm -f src/notes.txt.bak
  git add src/notes.txt
  a=$(plan_commit "feat(notes): shout the first line")
  sed -i.bak '1s/.*/one/' src/notes.txt && rm -f src/notes.txt.bak
  printf 'eleven\n' >> src/notes.txt
  git add src/notes.txt
  git commit -q -m "chore(notes): put the first line back, and one more"
  vbw_run prove
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${a:0:12} (P1.1) changed src/notes.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  [[ "$output" != *"undone by"* ]] || { echo "$output"; false; }
  undone_is '[]'
  jq -e '.evidence.passed == false and (.evidence.scope | length) == 1' .vbw/record.json
}

@test "R204: an undo that restores one of two files is partial: the commit is judged for both files" {
  local a
  printf 'one\n' > src/s1.txt
  printf 'two\n' > src/s2.txt
  git add src/s1.txt src/s2.txt
  a=$(plan_commit "feat(stray): two files")
  git rm -q src/s1.txt
  git commit -q -m "chore(stray): one of them out again"
  vbw_run prove
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${a:0:12} (P1.1) changed src/s1.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${a:0:12} (P1.1) changed src/s2.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  undone_is '[]'
  jq -e '(.evidence.scope | length) == 2' .vbw/record.json
}

@test "R204: an undo that touches one path more than the commit it undoes is not exact: the commit is judged" {
  local a
  a=$(stray 1)
  git rm -q src/stray1.txt
  printf 'more\n' >> README.md
  git add README.md
  git commit -q -m "chore(stray): out again, plus a note"
  vbw_run prove
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${a:0:12} (P1.1) changed src/stray1.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  undone_is '[]'
}

@test "R204: a mode-only change and its exact undo are cleared" {
  local a r
  git update-index --chmod=+x src/tool.sh
  a=$(plan_commit "feat(tool): executable")
  git log -1 --raw --no-abbrev --format= "$a" | grep -q '^:100644 100755 \([0-9a-f]\{40\}\) \1 M' || { git log -1 --raw --no-abbrev "$a"; false; }
  git update-index --chmod=-x src/tool.sh
  git commit -q -m "chore(tool): not executable after all"
  r=$(git rev-parse HEAD)
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope ok"* ]] || { echo "$output"; false; }
  undone_is "$(jq -nc --arg a "$a" --arg r "$r" '[{commit: $a, plan: "P1.1", by: $r}]')"
  [[ "$output" == *"$(line_entry "$a" "$r")"* ]] || { echo "$output"; false; }
}

@test "R204: a file added and deleted again is cleared; a file deleted and added back with the same content and mode is cleared" {
  local a r b s
  a=$(stray 1)
  git rm -q src/stray1.txt
  git commit -q -m "chore(stray): gone again"
  r=$(git rev-parse HEAD)
  git rm -q src/notes.txt
  b=$(plan_commit "feat(notes): drop the notes")
  printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n' > src/notes.txt
  git add src/notes.txt
  git commit -q -m "chore(notes): the notes are back"
  s=$(git rev-parse HEAD)
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope ok"* ]] || { echo "$output"; false; }
  undone_is "$(jq -nc --arg a "$a" --arg r "$r" --arg b "$b" --arg s "$s" '[{commit: $b, plan: "P1.1", by: $s}, {commit: $a, plan: "P1.1", by: $r}]')"
  [[ "$output" == *"$(line_entry "$a" "$r")"* ]] || { echo "$output"; false; }
  [[ "$output" == *"$(line_entry "$b" "$s")"* ]] || { echo "$output"; false; }
}

@test "R204: a re-apply after a revert is a fresh commit: it is judged, and so is the first commit again" {
  local a c
  a=$(stray 1)
  git revert --no-edit "$a" > /dev/null
  printf 'stray 1\n' > src/stray1.txt
  git add src/stray1.txt
  c=$(plan_commit "feat(stray): stray 1 again")
  vbw_run prove
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${a:0:12} (P1.1) changed src/stray1.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${c:0:12} (P1.1) changed src/stray1.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  undone_is '[]'
  jq -e '(.evidence.scope | length) == 2' .vbw/record.json
}

@test "R204: a revert of a revert clears nothing: the original is judged again" {
  local a
  a=$(stray 1)
  git revert --no-edit "$a" > /dev/null
  git revert --no-edit HEAD > /dev/null
  git log -1 --format=%s | grep -q '^Reapply'
  vbw_run prove
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${a:0:12} (P1.1) changed src/stray1.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  undone_is '[]'
  jq -e '(.evidence.scope | length) == 1' .vbw/record.json
}

@test "R204: a chain of apply, undo, apply, undo leaves all four unjudged, newest pair first" {
  local a1 b1 a2 b2
  a1=$(stray 1)
  git revert --no-edit "$a1" > /dev/null
  b1=$(git rev-parse HEAD)
  printf 'stray 1\n' > src/stray1.txt
  git add src/stray1.txt
  a2=$(plan_commit "feat(stray): stray 1 again")
  git revert --no-edit "$a2" > /dev/null
  b2=$(git rev-parse HEAD)
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope ok"* ]] || { echo "$output"; false; }
  undone_is "$(jq -nc --arg a1 "$a1" --arg b1 "$b1" --arg a2 "$a2" --arg b2 "$b2" '[{commit: $a2, plan: "P1.1", by: $b2}, {commit: $a1, plan: "P1.1", by: $b1}]')"
  [ "$(printf '%s\n' "$output" | grep -c 'undone by')" -eq 2 ] || { echo "$output"; false; }
}

@test "R204: an exact undo that carries a trailer of its own is not judged either, and both commits are listed" {
  local a b
  a=$(stray 1)
  git rm -q src/stray1.txt
  b=$(plan_commit "chore(stray): stray 1 out again")
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope ok"* ]] || { echo "$output"; false; }
  undone_is "$(jq -nc --arg a "$a" --arg b "$b" '[{commit: $b, plan: "P1.1", by: $a}, {commit: $a, plan: "P1.1", by: $b}]')"
  [[ "$output" == *"$(line_entry "$b" "$a")"* ]] || { echo "$output"; false; }
  [[ "$output" == *"$(line_entry "$a" "$b")"* ]] || { echo "$output"; false; }
}

@test "R204: a cleared commit whose trailer names a shipped milestone's plan is not listed; a current one beside it is" {
  local a r old
  printf 'old\n' > src/elsewhere.txt
  git add src/elsewhere.txt
  old=$(plan_commit "feat(old): long ago" P0.1)
  git revert --no-edit "$old" > /dev/null
  a=$(stray 1)
  git revert --no-edit "$a" > /dev/null
  r=$(git rev-parse HEAD)
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  undone_is "$(jq -nc --arg a "$a" --arg r "$r" '[{commit: $a, plan: "P1.1", by: $r}]')"
  [[ "$output" != *"${old:0:12}"* ]] || { echo "$output"; false; }
}

@test "R204: a commit of the current plan that nothing undoes is judged exactly as before, in the same words" {
  local a
  a=$(stray 1)
  vbw_run prove
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  scope: ${a:0:12} (P1.1) changed src/stray1.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  undone_is '[]'
  vbw_run next --json
  echo "$output" | jq -e '.action == "scope"'
}

# --- a fixed number of git processes ----------------------------------------

# counted_prove DIR: vbw prove in DIR with a counting stand-in git first on PATH; prints how many git processes ran.
counted_prove() {
  local real
  real=$(command -v git)
  mkdir -p "$TEST_ROOT/standin"
  printf '#!/bin/sh\nprintf "x\\n" >> "%s"\nexec "%s" "$@"\n' "$TEST_ROOT/gitcount" "$real" > "$TEST_ROOT/standin/git"
  chmod +x "$TEST_ROOT/standin/git"
  rm -f "$TEST_ROOT/gitcount"
  (cd "$1" && PATH="$TEST_ROOT/standin:$PATH" "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 < /dev/null) || { cat "$TEST_ROOT/prove.out"; return 1; }
  wc -l < "$TEST_ROOT/gitcount" | tr -d ' '
}

# plan_history DIR N: N commits of P1.1 on its own file src/pay.txt (no violation, nothing undone) in DIR, a copy of the fixture.
plan_history() {
  local i
  (
    cd "$1" || exit 1
    for ((i = 1; i <= $2; i++)); do
      printf 'paid\n# change %s\n' "$i" > src/pay.txt
      git add src/pay.txt
      plan_commit "feat(pay): change $i" > /dev/null
    done
    [ "$(git log --format='%(trailers:key=VBW-Plan,valueonly)' | grep -c '^P1.1$')" -eq "$2" ]
  )
}

@test "R204: the scope check costs the same number of git processes for 5 plan-trailer commits as for 50" {
  local five fifty
  # Two copies of the never-proved fixture, so the only difference between the proofs is the history's length.
  cp -R "$PROJECT" "$TEST_ROOT/fifty"
  plan_history "$PROJECT" 5
  plan_history "$TEST_ROOT/fifty" 50
  five=$(counted_prove "$PROJECT")
  fifty=$(counted_prove "$TEST_ROOT/fifty")
  [ "$five" -gt 0 ] || { echo "no git process counted"; false; }
  [ "$fifty" -eq "$five" ] || { echo "git processes: $five for 5 commits, $fifty for 50"; false; }
}
