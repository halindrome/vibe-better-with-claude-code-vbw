#!/usr/bin/env bats
# R184: in a project where the VBW plugin is turned off (enabledPlugins
# "vbw@vbw-marketplace": false), VBW's status line script prints nothing,
# writes nothing and exits 3: the signal the statusLine setting reads to hand
# over to the user's earlier status line (tests/statusline-handback.bats). The
# on/off answer follows Claude Code's order of settings files: the project's
# .claude/settings.local.json, then its .claude/settings.json, then the user's
# settings.json (CLAUDE_CONFIG_DIR, else ~/.config/claude-code, else ~/.claude).
# The script itself never runs the saved earlier status line (D356). Where VBW
# is on, nothing changes. L1: the script is run directly.

load helper

setup() {
  vbw_setup
  vbw_git_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  USER_SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
}

teardown() { vbw_teardown; }

cc_json() {
  jq -nc --arg d "${DIR:-$PROJECT}" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, cwd: $d,
    model: {display_name: "Sonnet 5.5"}, version: "2.1.286",
    cost: {total_cost_usd: 1.4234, total_duration_ms: 622000, total_api_duration_ms: 355000, total_lines_added: 303, total_lines_removed: 12},
    context_window: {used_percentage: 31, total_input_tokens: 62000, total_output_tokens: 1200, context_window_size: 200000}}'
}

render() { cc_json | NO_COLOR=1 bash "$SL"; }

# vbw_in FILE true|false: the settings file FILE turns VBW on or off.
vbw_in() {
  mkdir -p "$(dirname "$1")"
  jq -n --argjson v "$2" '{enabledPlugins: {"vbw@vbw-marketplace": $v}}' > "$1"
}

hidden() {
  run render
  [ "$status" -eq 3 ] && [ -z "$output" ] || {
    echo "expected no output and exit 3 (VBW turned off), got exit $status:"
    printf '%s\n' "$output"
    false
  }
}

shown() {
  run render
  [ "$status" -eq 0 ] && [ "${#lines[@]}" -eq 4 ] && [[ "${lines[0]}" == "[VBW] "* ]] || {
    echo "expected the four VBW lines and exit 0, got exit $status:"
    printf '%s\n' "$output"
    false
  }
}

# snapshot: every file under the project with its checksum.
snapshot() { find "$PROJECT" -type f -exec cksum {} + | sort; }

@test "R184: the project's .claude/settings.json turns VBW off: nothing printed, exit 3" {
  vbw_in "$PROJECT/.claude/settings.json" false
  hidden
}

@test "R184: the user's settings.json turns VBW off when the project says nothing; the project's true wins over it" {
  vbw_in "$USER_SETTINGS" false
  hidden
  mkdir -p "$PROJECT/.claude"
  printf '{"model": "opus"}\n' > "$PROJECT/.claude/settings.json"
  hidden
  vbw_in "$PROJECT/.claude/settings.json" true
  shown
}

@test "R184: the project's .claude/settings.local.json wins over its .claude/settings.json, both ways" {
  vbw_in "$PROJECT/.claude/settings.json" false
  vbw_in "$PROJECT/.claude/settings.local.json" true
  shown
  vbw_in "$PROJECT/.claude/settings.json" true
  vbw_in "$PROJECT/.claude/settings.local.json" false
  hidden
  # The local file wins over the user's file too.
  rm -f "$PROJECT/.claude/settings.json"
  vbw_in "$USER_SETTINGS" false
  vbw_in "$PROJECT/.claude/settings.local.json" true
  shown
}

@test "R184: the user's settings file is found as VBW finds it: CLAUDE_CONFIG_DIR, else ~/.config/claude-code, else ~/.claude" {
  vbw_in "$HOME/.claude/settings.json" false
  run bash -c 'cc=$1; printf "%s\n" "$cc" | env -u CLAUDE_CONFIG_DIR NO_COLOR=1 bash "$2"' _ "$(cc_json)" "$SL"
  [ "$status" -eq 3 ] && [ -z "$output" ] || {
    echo "\$HOME/.claude/settings.json says false, no CLAUDE_CONFIG_DIR: got exit $status"
    printf '%s\n' "$output"
    false
  }
  # ~/.config/claude-code exists: it is the user's folder, and says nothing.
  mkdir -p "$HOME/.config/claude-code"
  printf '{}\n' > "$HOME/.config/claude-code/settings.json"
  run bash -c 'cc=$1; printf "%s\n" "$cc" | env -u CLAUDE_CONFIG_DIR NO_COLOR=1 bash "$2"' _ "$(cc_json)" "$SL"
  [ "$status" -eq 0 ] && [ "${#lines[@]}" -eq 4 ] || {
    echo "\$HOME/.config/claude-code is the user's folder and says nothing: got exit $status"
    printf '%s\n' "$output"
    false
  }
  # CLAUDE_CONFIG_DIR comes first.
  mkdir -p "$TEST_ROOT/config"
  vbw_in "$TEST_ROOT/config/settings.json" false
  run bash -c 'cc=$1; printf "%s\n" "$cc" | CLAUDE_CONFIG_DIR="$3" NO_COLOR=1 bash "$2"' _ "$(cc_json)" "$SL" "$TEST_ROOT/config"
  [ "$status" -eq 3 ] && [ -z "$output" ] || {
    echo "CLAUDE_CONFIG_DIR's settings.json says false: got exit $status"
    printf '%s\n' "$output"
    false
  }
}

@test "R184: started in a subfolder, the settings are read from the project folder (the nearest folder up holding .git)" {
  mkdir -p "$PROJECT/src/deep"
  vbw_in "$PROJECT/.claude/settings.json" false
  DIR="$PROJECT/src/deep" hidden
}

@test "R184: nothing that does not turn VBW off changes anything: missing files, no entry, another plugin off, or a file that is not JSON" {
  shown
  local body
  for body in '{}' '{"enabledPlugins": {}}' '{"enabledPlugins": {"other@market": false}}' 'not json {' '{"enabledPlugins": {"vbw@vbw-marketplace": true}}'; do
    rm -rf "$PROJECT/.claude" "$USER_SETTINGS"
    mkdir -p "$PROJECT/.claude"
    printf '%s\n' "$body" > "$PROJECT/.claude/settings.json"
    shown
    printf '%s\n' "$body" > "$PROJECT/.claude/settings.local.json"
    shown
    rm -rf "$PROJECT/.claude"
    printf '%s\n' "$body" > "$USER_SETTINGS"
    shown
  done
}

@test "R184: where VBW is on, the output is byte-for-byte the same as with no settings at all, and the cost file is still written" {
  "$VBW" init > /dev/null
  render > "$TEST_ROOT/plain.txt"
  rm -f "$PROJECT/.vbw/runtime/cost.s1.json"
  vbw_in "$PROJECT/.claude/settings.json" true
  printf '{"enabledPlugins": {"other@market": false}, "theme": "dark"}\n' > "$USER_SETTINGS"
  render > "$TEST_ROOT/on.txt"
  cmp "$TEST_ROOT/plain.txt" "$TEST_ROOT/on.txt" || {
    echo "the output changed where VBW is on:"
    diff "$TEST_ROOT/plain.txt" "$TEST_ROOT/on.txt"
    false
  }
  jq -e '.session == "s1" and .usd == 1.4234' "$PROJECT/.vbw/runtime/cost.s1.json"
}

@test "R184: where VBW is off, the status line writes no file anywhere in the project" {
  "$VBW" init > /dev/null
  rm -f "$PROJECT"/.vbw/runtime/cost.*.json
  vbw_in "$PROJECT/.claude/settings.json" false
  snapshot > "$TEST_ROOT/before.txt"
  hidden
  snapshot > "$TEST_ROOT/after.txt"
  cmp "$TEST_ROOT/before.txt" "$TEST_ROOT/after.txt" || {
    echo "files changed in a project where VBW is off:"
    diff "$TEST_ROOT/before.txt" "$TEST_ROOT/after.txt"
    false
  }
  [ ! -e "$PROJECT/.vbw/runtime/cost.s1.json" ]
  # Without a runtime folder, none is made.
  rm -rf "$PROJECT/.vbw/runtime"
  hidden
  [ ! -e "$PROJECT/.vbw/runtime" ]
}

@test "R184: the script never runs the saved earlier status line, nor any command from the settings (D356)" {
  local mark="$TEST_ROOT/ran"
  jq -n --arg c "touch '$mark.saved'" '{type: "command", command: $c}' > "$CLAUDE_CONFIG_DIR/vbw-statusline-previous.json"
  jq -n --arg c "touch '$mark.setting'" '{statusLine: {type: "command", command: $c}, enabledPlugins: {"vbw@vbw-marketplace": false}}' > "$USER_SETTINGS"
  hidden
  [ ! -e "$mark.saved" ] && [ ! -e "$mark.setting" ] || {
    echo "vbw-statusline.sh ran a command read from a file"
    false
  }
  # Where VBW is on, it never runs them either.
  vbw_in "$PROJECT/.claude/settings.json" true
  shown
  [ ! -e "$mark.saved" ] && [ ! -e "$mark.setting" ]
}
