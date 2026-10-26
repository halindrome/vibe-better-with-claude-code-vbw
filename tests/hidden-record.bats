#!/usr/bin/env bats
# R208 (docs/record.md, docs/diagnostics.md): VBW's own plan files
# (.vbw/record.json, .vbw/spec.md, .vbw/map.md) are never hidden by a project's
# git ignore rule for files. vbw init writes .vbw/.gitignore with runtime/ and the
# un-hide lines !record.json, !spec.md, !map.md and !.gitignore, says so in one
# line, and in an initialized project adds only the missing lines, keeps the
# user's lines and leaves the file byte-identical when run again. Every VBW
# commit of its own files (record_commit) first adds the missing un-hide lines and
# commits .vbw/.gitignore with the others, so a record.json a project-wide *.json
# rule would hide is committed, and a spec.md a *.md rule would hide is visible to
# git until the next full commit takes it, as in any project (the project's
# .gitignore, .git/info/exclude and a global excludes file). When an own file that
# exists is untracked and still ignored after the lines (a rule such as .vbw/ or *
# hiding the folder), vbw init prints the rule's source as git check-ignore -v gives
# it (file, line, pattern) with the fix ("remove that line, or change it to
# .vbw/runtime/"); vbw doctor fails with the same; vbw approve refuses with it,
# exit 1, adding no decision, granting no consent, making no commit; vbw next
# names it among the reasons the contract is not ready (R171); record_commit's
# non-strict form prints a vbw: warning: line naming the file and the rule's
# source line, never skipping the file silently. A project with no such rule
# prints nothing new. This file holds the commit path and vbw approve; the init,
# doctor and next cases are tests/hidden-record-commands.bats. L1: the kernel on
# fixture projects.

load helper
load fixture-helper

UNHIDE=$'runtime/\n!record.json\n!spec.md\n!map.md\n!.gitignore'
SAID_RE='keeps its plan files visible to git through \.vbw/\.gitignore'
HIDDEN_RE='\.vbw/record\.json is hidden from git by \.gitignore:1:\.vbw/'
FIX='remove that line, or change it to .vbw/runtime/'

# repo: a git repository with one commit, not yet a VBW project.
repo() {
  vbw_setup
  vbw_git_project
}

# planned_hidden: a project whose contract is otherwise ready (spec, plan, check
# file committed) but whose .vbw/ is untracked and hidden by a .vbw/ rule.
planned_hidden() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"]}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying works", check: "C1"}]}' | "$VBW" apply > /dev/null
  printf '.vbw/\n' > .gitignore
  git add .gitignore src tests && git commit -q -m "feat(shop): start"
}

setup_file() {
  fixture_build repo repo
  fixture_build hidden planned_hidden
}
setup() { fixture_copy repo; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

tracked() { git ls-files --error-unmatch -- "$1" > /dev/null 2>&1; }

@test "R208: a project-wide *.json rule in the project's .gitignore no longer hides the record: VBW's next commit commits it and .vbw/.gitignore, and the spec is visible to git" {
  printf '*.json\n*.md\n' > .gitignore
  git add .gitignore && git commit -q -m "chore: ignore json and md"
  "$VBW" init > /dev/null
  vbw_run todo add "a note"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  tracked .vbw/record.json || { git status --porcelain --ignored; false; }
  tracked .vbw/.gitignore
  [ "$(git log -1 --format=%s)" = "chore(vbw): todo T1 added" ] || { git log -3 --oneline; false; }
  # A commit of the record alone never sweeps the spec in, as in any project; but it is no longer hidden.
  ! git check-ignore -q -- .vbw/spec.md || { git check-ignore -v -- .vbw/spec.md; false; }
  git ls-files --others --exclude-standard -- .vbw/spec.md | grep -qx '.vbw/spec.md' || { git status --porcelain --ignored; false; }
  [[ "$output" != *warning* && "$output" != *hidden* ]] || { echo "$output"; false; }
}

@test "R208: the same with the rule in .git/info/exclude and in a global excludes file" {
  printf '*.json\n' >> .git/info/exclude
  "$VBW" init > /dev/null
  "$VBW" todo add "a note" > /dev/null
  tracked .vbw/record.json || { git status --porcelain --ignored; false; }
  vbw_teardown
  fixture_copy repo
  printf '*.json\n*.md\n' > "$TEST_ROOT/excludes"
  git config --global core.excludesFile "$TEST_ROOT/excludes"
  "$VBW" init > /dev/null
  "$VBW" todo add "a note" > /dev/null
  tracked .vbw/record.json || { git status --porcelain --ignored; false; }
  ! git check-ignore -q -- .vbw/spec.md || { git check-ignore -v -- .vbw/spec.md; false; }
}

@test "R208: an existing project gets the un-hide lines at its next VBW commit, committed along with the record" {
  "$VBW" init > /dev/null
  printf 'runtime/\n' > .vbw/.gitignore
  git add .vbw && git commit -q -m "chore(vbw): init under an older VBW"
  printf '*.json\n' > .gitignore
  git add .gitignore && git commit -q -m "chore: ignore json"
  vbw_run todo add "a note"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat .vbw/.gitignore)" = "$UNHIDE" ] || { cat .vbw/.gitignore; false; }
  git show --name-only --format= HEAD | grep -qx '.vbw/.gitignore' || { git show --name-only --format= HEAD; false; }
  git show --name-only --format= HEAD | grep -qx '.vbw/record.json' || { git show --name-only --format= HEAD; false; }
  [ -z "$(git status --porcelain -- .vbw)" ] || { git status --porcelain -- .vbw; false; }
}

@test "R208: vbw approve refuses with that message, exit 1, adding no decision, granting no consent and making no commit" {
  fixture_copy hidden
  local head decisions
  head=$(git rev-parse HEAD)
  decisions=$(jq '.decisions | length' .vbw/record.json)
  vbw_run approve
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"the contract is not ready for approval:"* ]] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE "$HIDDEN_RE" || { echo "$output"; false; }
  [[ "$output" == *"$FIX"* ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ "$(jq '.decisions | length' .vbw/record.json)" = "$decisions" ]
  run "$VBW" show contract < /dev/null
  printf '%s\n' "$output" | head -n 1 | grep -q 'NOT APPROVED' || { echo "$output"; false; }
}

@test "R208: record_commit's non-strict form prints a vbw: warning: line naming the hidden file and the rule's source line" {
  "$VBW" init > /dev/null
  printf '.vbw/\n' > .gitignore
  git add .gitignore && git commit -q -m "chore: hide .vbw"
  vbw_run todo add "a note"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE "^vbw: warning: .*$HIDDEN_RE" || { echo "$output"; false; }
  [[ "$output" == *"$FIX"* ]] || { echo "$output"; false; }
  if tracked .vbw/record.json; then echo "the hidden record was committed"; false; fi
}
