#!/usr/bin/env bats
# R184, the whole path: the statusLine setting written by vbw statusline on,
# run as Claude Code runs it (sh -c, in the project, its JSON on stdin), with
# this plugin installed in the plugin cache. Where the project turns VBW off,
# the user sees their earlier status line, or nothing; where VBW is on, exactly
# what VBW's script prints. A setting from an older VBW, not yet updated,
# shows no VBW line where VBW is off. L1 (no Claude Code process).

load helper

OLD_CMD='bash -c '"'"'for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; f=$(ls -1 "$_d"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh 2>/dev/null | sort -V | tail -1 || true); [ -f "$f" ] && exec bash "$f"; done'"'"' '
MINE_CMD='MY_LINE=1 bash "$HOME/it'"'"'s my line.sh"'

setup() {
  vbw_setup
  vbw_git_project
  SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
  local cache="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.9"
  mkdir -p "$cache"
  cp -R "$PLUGIN_ROOT/." "$cache/"
  printf '#!/bin/sh\ncat > "$HOME/mine.input"\necho "my own line $MY_LINE"\n' > "$HOME/it's my line.sh"
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, cwd: $d,
    model: {display_name: "Sonnet 5.5"}, version: "2.1.286", cost: {total_cost_usd: 1.25},
    context_window: {used_percentage: 31, total_input_tokens: 62000, context_window_size: 200000}}' > "$TEST_ROOT/cc.json"
}

teardown() { vbw_teardown; }

vbw_off() {
  mkdir -p "$PROJECT/.claude"
  printf '{"enabledPlugins": {"vbw@vbw-marketplace": false}}\n' > "$PROJECT/.claude/settings.json"
}

setting() {
  local cmd
  cmd=$(jq -r '.statusLine.command' "$SETTINGS")
  run env NO_COLOR=1 sh -c "$cmd" < "$TEST_ROOT/cc.json"
}

@test "R184: in a project that turns VBW off, the real setting shows the user's earlier status line with Claude Code's input" {
  jq -n --arg c "$MINE_CMD" '{statusLine: {type: "command", command: $c}}' > "$SETTINGS"
  "$VBW" statusline on > /dev/null
  vbw_off
  setting
  [ "$status" -eq 0 ] && [ "$output" = "my own line 1" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output"
    false
  }
  jq -e --slurpfile a "$TEST_ROOT/cc.json" '. == $a[0]' "$HOME/mine.input"
}

@test "R184: in a project that turns VBW off, with no earlier status line, nothing shows: no VBW line, no 'unavailable'" {
  "$VBW" statusline on > /dev/null
  vbw_off
  setting
  [ "$status" -eq 0 ] && [ -z "$output" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output"
    false
  }
}

@test "R184: where VBW is on, the real setting prints exactly what VBW's script prints, and the earlier status line never runs" {
  "$VBW" init > /dev/null
  jq -n --arg c "$MINE_CMD" '{statusLine: {type: "command", command: $c}}' > "$SETTINGS"
  "$VBW" statusline on > /dev/null
  mkdir -p "$PROJECT/.claude"
  printf '{"enabledPlugins": {"vbw@vbw-marketplace": true}}\n' > "$PROJECT/.claude/settings.json"
  setting
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TEST_ROOT/setting.txt"
  NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" < "$TEST_ROOT/cc.json" > "$TEST_ROOT/script.txt"
  cmp "$TEST_ROOT/setting.txt" "$TEST_ROOT/script.txt"
  [[ "${lines[0]}" == "[VBW] project with space"* ]]
  [ ! -e "$HOME/mine.input" ]
}

@test "R184: a setting from an older VBW, not yet updated, shows no VBW line in a project that turns VBW off" {
  jq -n --arg c "$OLD_CMD" '{statusLine: {type: "command", command: $c, refreshInterval: 5}}' > "$SETTINGS"
  vbw_off
  setting
  [ -z "$output" ] || {
    echo "the older setting still shows VBW:"
    printf '%s\n' "$output"
    false
  }
}
