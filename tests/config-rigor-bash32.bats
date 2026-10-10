#!/usr/bin/env bats
# R154: vbw config rigor works under macOS /bin/bash 3.2 (the floor), where a
# process substitution handed to a function is closed before the function's
# later commands read it. The kernel runs here under /bin/bash explicitly, so
# the test is the bash 3.2 floor on macOS and plain bash elsewhere.

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

@test "R154: vbw config rigor under /bin/bash re-tiers an unstarted phase and saves the record" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  load rigor-helper
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  run /bin/bash "$VBW" config rigor deep
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"record update failed"* ]]
  jq -e '.settings.rigor == "deep" and .phases[0].tier == "deep"' .vbw/record.json
  run /bin/bash "$VBW" config rigor auto
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.settings.rigor == "auto" and (.phases[0].reasons | any(.[]; test("forced")) | not)' .vbw/record.json
}
