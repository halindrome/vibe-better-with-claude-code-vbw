#!/usr/bin/env bats
# R149: a file VBW uses to hand record-sized data to jq lives inside the
# project (.vbw/runtime or the clone's git directory, never the system's
# temporary folder) and is gone when the command ends, whether it succeeded or
# failed. Run on the twins of big-record-helper.bash (project folders with a
# space) with TMPDIR set to an empty folder of the test, which must stay
# empty. After every command, the large twin's .vbw/runtime holds only VBW's
# kept state (the approved contract, the last next answer and the proof's
# unit list next keeps, the status line glance, autonomy files, the check
# gate and kept check output) and its git
# directory's vbw folder only JSON state files
# (clean_step, big-record-helper.bash). The commands that succeed are walked
# in big-record-commands.bats, where every step is a clean step; this file
# walks the ones that fail. Statically, every mktemp in shipped shell code
# names its folder, so nothing falls back to the system's temporary folder
# (here-strings of record-sized data are refused by
# tests/record-args-rule.bats). L1; the Claude Code sandbox itself is not run
# here.

load helper
load big-record-helper
load fixture-helper

setup_file() { fixture_build twins twin_fixture; }
setup() { twin_copy twins; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

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
