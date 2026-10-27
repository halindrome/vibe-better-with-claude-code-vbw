#!/usr/bin/env bats
# Sound setting (T18): vbw config set sound off|<folder under plugin/assets/audio>
# is this clone's own choice, kept like check_jobs in
# $(git-common-dir)/vbw/settings.json as {"sound": "<value>"}, never in the
# shared record. default removes it (the panel then picks among every shipped
# sound), vbw config shows it, an unknown name is refused with the list of
# folders and changes nothing.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  SETTINGS="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/settings.json"
}

teardown() { vbw_teardown; }

@test "sound accepts off and every folder under assets/audio and stores each in this clone's settings, not in the record" {
  local v dir
  cp .vbw/record.json "$TEST_ROOT/before.json"
  for dir in "$PLUGIN_ROOT"/assets/audio/*/; do
    v=$(basename "$dir")
    vbw_run config set sound "$v"
    [ "$status" -eq 0 ]
    [ "$output" = "sound = $v" ]
    jq -e --arg v "$v" '.sound == $v' "$SETTINGS"
  done
  vbw_run config set sound off
  [ "$status" -eq 0 ]
  jq -e '.sound == "off"' "$SETTINGS"
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "sound keeps check_jobs, and sound default removes only itself" {
  "$VBW" config set check_jobs 2 > /dev/null
  "$VBW" config set sound darth > /dev/null
  jq -e '.sound == "darth" and .check_jobs == 2' "$SETTINGS"
  vbw_run config set sound default
  [ "$status" -eq 0 ]
  [ "$output" = "sound = default" ]
  jq -e 'has("sound") | not' "$SETTINGS"
  jq -e '.check_jobs == 2' "$SETTINGS"
  "$VBW" config set check_jobs default > /dev/null
  jq -e 'has("check_jobs") | not' "$SETTINGS"
}

@test "an unknown sound is refused with the list of folders and changes nothing" {
  "$VBW" config set sound darth > /dev/null
  cp "$SETTINGS" "$TEST_ROOT/before.json"
  # The list is the folders as shipped: "off, a, b, ... or z".
  local v names list
  names=$(for d in "$PLUGIN_ROOT"/assets/audio/*/; do basename "$d"; done | LC_ALL=C sort)
  list="off, $(printf '%s\n' "$names" | sed '$d' | paste -sd ',' - | sed 's/,/, /g') or $(printf '%s\n' "$names" | tail -n 1)"
  for v in nosuch DARTH ../darth "" assets; do
    vbw_run config set sound "$v"
    [ "$status" -ne 0 ] || { echo "'$v' accepted"; false; }
    [[ "$output" == *"sound must be $list (or default)"* ]] || { echo "$output"; false; }
  done
  cmp "$SETTINGS" "$TEST_ROOT/before.json"
}

@test "vbw config shows sound: default when unset, the value when set" {
  vbw_run config
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nsound: default\n'* ]]
  "$VBW" config set sound charlize > /dev/null
  vbw_run config
  [[ "$output" == *$'\nsound: charlize\n'* ]]
}

@test "a damaged or unknown stored sound reads as default" {
  mkdir -p "${SETTINGS%/*}"
  printf '{"sound": "../x"}\n' > "$SETTINGS"
  vbw_run config
  [[ "$output" == *$'\nsound: default\n'* ]]
  printf 'not json' > "$SETTINGS"
  vbw_run config
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nsound: default\n'* ]]
}
