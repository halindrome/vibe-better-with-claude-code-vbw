#!/usr/bin/env bats
# R149: a file VBW uses to hand record-sized data to jq lives inside the
# project (.vbw/runtime or the clone's git directory, never the system's
# temporary folder) and is gone when the command ends, whether it succeeded or
# failed. Run on the twins of big-record-helper.bash (project folders with a
# space) with TMPDIR set to an empty folder of the test, which must stay
# empty. After every command, the large twin's .vbw/runtime holds only VBW's
# kept state (the approved contract, the last next answer, the status line
# glance, autonomy files, the unfinished-proof marker, the check gate and kept
# check output) and its git directory's vbw folder only JSON state files.
# Statically, every mktemp in shipped shell code names its folder, so nothing
# falls back to the system's temporary folder (here-strings of record-sized
# data are refused by tests/record-args-rule.bats). L1; the Claude Code
# sandbox itself is not run here.

load helper
load big-record-helper

setup() {
  vbw_setup
  twins
  mkdir -p "$TEST_ROOT/tmpdir"
  export TMPDIR="$TEST_ROOT/tmpdir"
}

teardown() { vbw_teardown; }

# leftovers DIR: what a command left in DIR's .vbw/runtime and in its git
# directory's vbw folder beyond VBW's kept state, one entry per line.
leftovers() {
  local gd
  (cd "$1/.vbw/runtime" && find . -mindepth 1 -path ./output -prune -o -print) | sed 's|^\./||' \
    | grep -vxE 'approved-contract\.json|next\.json|step\.json|glance\.json|run-open|auto\.[A-Za-z0-9_-]+\.json|prove\.unfinished|gate|output' || true
  gd=$(git -C "$1" rev-parse --git-common-dir)
  case "$gd" in /*) ;; *) gd="$1/$gd" ;; esac
  [ ! -d "$gd/vbw" ] || (cd "$gd/vbw" && find . -mindepth 1 -print) | sed 's|^\./||' | grep -vE '^[A-Za-z0-9_-]+\.json$' || true
}

# clean_step CMD...: the command behaves the same in both twins (twin_step),
# nothing was written to TMPDIR, and neither twin keeps a leftover file.
clean_step() {
  twin_step "$@"
  [ -z "$(ls -A "$TMPDIR")" ] || { echo "vbw $* wrote to TMPDIR: $(ls -A "$TMPDIR")"; return 1; }
  local s b
  s=$(leftovers "$SMALL")
  b=$(leftovers "$BIG")
  [ -z "$b" ] || { printf 'vbw %s left files behind on the large record:\n%s\n' "$*" "$b"; return 1; }
  [ -z "$s" ] || { printf 'vbw %s left files behind on the small record:\n%s\n' "$*" "$s"; return 1; }
}

@test "R149: every mktemp in shipped shell code names a folder, so no scratch file goes to the system's temporary folder" {
  local f line bad=""
  while IFS= read -r f; do
    while IFS= read -r line; do
      [[ "$line" =~ ^[0-9]+:[[:space:]]*# ]] && continue
      [[ "$line" =~ mktemp([[:space:]]+-d)?[[:space:]]+\"[^\"]*/[^\"]*XXXXXX\" ]] || bad="$bad$f:$line"$'\n'
    done < <(grep -n 'mktemp' "$f" || true)
  done < <(find "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts" -type f \( -name '*.sh' -o -name vbw \))
  [ -z "$bad" ] || { printf 'mktemp without a named folder:\n%s' "$bad"; false; }
}

@test "R149: reads and writes of a record over 2 MB leave no scratch file behind and never use the system's temporary folder" {
  clean_step status
  clean_step next --json
  clean_step show phase P1
  clean_step show roadmap
  clean_step decide "Keep the history" "the owner wants it"
  clean_step todo add "Gift cards"
  twin_doc > "$TEST_ROOT/doc.json"
  TWIN_IN="$TEST_ROOT/doc.json" clean_step apply
  clean_step show contract
  clean_step approve
  clean_step req accept R53
}

@test "R149: a build, a proof and a QA verdict on a record over 2 MB leave no scratch file behind" {
  twin_doc > "$TEST_ROOT/doc.json"
  TWIN_IN="$TEST_ROOT/doc.json" clean_step apply
  clean_step approve
  clean_step run start build P51.1 P52.1
  in_twins sh -c 'printf "a\n" > src/a.txt && printf "b\n" > src/b.txt'
  clean_step commit P51.1 "feat(p51): part a"
  clean_step plan "done" P51.1
  clean_step commit P52.1 "feat(p52): part b"
  clean_step plan "done" P52.1
  clean_step run end
  clean_step prove --full
  clean_step check C101
  clean_step qa record P51 pass deep
  clean_step show phase P51
  clean_step next --json
}

@test "R149: commands that fail on a record over 2 MB leave no scratch file behind either" {
  twin_doc > "$TEST_ROOT/doc.json"
  TWIN_IN="$TEST_ROOT/doc.json" clean_step apply
  clean_step approve
  TWIN_ANY=1 clean_step qa record P51 pass deep
  TWIN_ANY=1 clean_step req accept R51
  TWIN_ANY=1 clean_step show phase P999
  clean_step run start build P51.1 P52.1
  in_twins sh -c 'printf "a\n" > src/a.txt && printf "b\n" > src/b.txt'
  clean_step commit P51.1 "feat(p51): part a"
  clean_step plan "done" P51.1
  clean_step commit P52.1 "feat(p52): part b"
  clean_step plan "done" P52.1
  clean_step run end
  in_twins sh -c 'printf "c\n" > src/b.txt && git commit -q -am "fix(p52): break part b"'
  TWIN_ANY=1 clean_step prove --full
  jq -e '.evidence.passed == false' "$BIG/.vbw/record.json"
  TWIN_ANY=1 clean_step qa record P52 pass deep
}
