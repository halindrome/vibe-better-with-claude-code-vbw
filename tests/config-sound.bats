#!/usr/bin/env bats
# Sound setting (T18): vbw config set sound off|<folder under plugin/assets/audio>
# stores record.settings.sound, default removes it (the panel then picks among
# every shipped sound), vbw config shows it, an unknown name is refused with the
# list of folders and changes nothing.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

@test "sound accepts off and every folder under assets/audio and stores each in the record's settings" {
  local v dir
  for dir in "$PLUGIN_ROOT"/assets/audio/*/; do
    v=$(basename "$dir")
    vbw_run config set sound "$v"
    [ "$status" -eq 0 ]
    [ "$output" = "sound = $v" ]
    jq -e --arg v "$v" '.settings.sound == $v' .vbw/record.json
  done
  vbw_run config set sound off
  [ "$status" -eq 0 ]
  jq -e '.settings.sound == "off"' .vbw/record.json
}

@test "sound default removes the setting" {
  "$VBW" config set sound darth > /dev/null
  vbw_run config set sound default
  [ "$status" -eq 0 ]
  [ "$output" = "sound = default" ]
  jq -e '.settings | has("sound") | not' .vbw/record.json
}

@test "an unknown sound is refused with the list of folders and changes nothing" {
  cp .vbw/record.json "$TEST_ROOT/before.json"
  local v
  for v in nosuch DARTH ../darth "" assets; do
    vbw_run config set sound "$v"
    [ "$status" -ne 0 ] || { echo "'$v' accepted"; false; }
    [[ "$output" == *"sound must be off, arnold, charlize or darth (or default)"* ]] || { echo "$output"; false; }
  done
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "vbw config shows sound: default when unset, the value when set" {
  vbw_run config
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nsound: default\n'* ]]
  "$VBW" config set sound charlize > /dev/null
  vbw_run config
  [[ "$output" == *$'\nsound: charlize\n'* ]]
}
