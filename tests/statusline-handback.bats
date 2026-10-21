#!/usr/bin/env bats
# R184: the statusLine setting VBW writes (vbw statusline on) hands over to the
# user's earlier status line where VBW is turned off. The installed VBW's
# script says "off" by printing nothing and exiting 3 (tests/statusline-off.bats);
# the command Claude Code runs from the settings then runs the earlier status
# line itself, with the same JSON input Claude Code sent, so VBW never runs a
# command read from a file (D356). With no earlier status line it shows nothing.
# A setting written by an older VBW is updated in place by vbw statusline on
# (and by a session that starts in a VBW project), and vbw doctor names it.
# L1: the installed script is a stand-in in a plugin cache under the test's
# Claude config folder; the setting is run with sh -c, as Claude Code runs it.

load helper

# The setting VBW wrote before this change (and VBW 1 before it).
OLD_CMD='bash -c '"'"'for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; f=$(ls -1 "$_d"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh 2>/dev/null | sort -V | tail -1 || true); [ -f "$f" ] && exec bash "$f"; done'"'"' '

# The user's earlier status line: quotes, a space, a variable and an
# environment prefix, all as the user wrote them.
MINE_CMD='MY_LINE=1 bash "$HOME/it'"'"'s my line.sh"'

setup() {
  vbw_setup
  vbw_git_project
  SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
  BACKUP="$CLAUDE_CONFIG_DIR/vbw-statusline-previous.json"
  CACHE="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.9/scripts"
  mkdir -p "$CACHE"
  # The earlier status line keeps what it was given and prints one line.
  printf '#!/bin/sh\ncat > "$HOME/mine.input"\necho "my own line $MY_LINE"\n' > "$HOME/it's my line.sh"
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, cwd: $d,
    model: {display_name: "Sonnet 5.5"}, version: "2.1.286", cost: {total_cost_usd: 1.25}}' > "$TEST_ROOT/cc.json"
}

teardown() { vbw_teardown; }

# installed off|on: the installed VBW's status line script is a stand-in that
# reads its input as the real one does (with a timeout), then says VBW is off
# (no output, exit 3) or prints one VBW line.
installed() {
  {
    printf '#!/usr/bin/env bash\nwhile IFS= read -t 1 -r l; do :; done\n'
    case "$1" in
      off) printf 'exit 3\n' ;;
      on) printf 'echo "[VBW] stand-in"\n' ;;
    esac
  } > "$CACHE/vbw-statusline.sh"
}

# settings_with STATUSLINE_JSON [EXTRA_JSON]: the user's settings.json.
settings_with() {
  # The default is set apart: bash 3.2 keeps the backslash in a brace-literal default.
  local extra="${2:-}"
  [ -n "$extra" ] || extra='{}'
  jq -n --argjson s "$1" --argjson x "$extra" '$x + {statusLine: $s}' > "$SETTINGS"
}

mine() { jq -nc --arg c "$MINE_CMD" '{type: "command", command: $c, padding: 0}'; }

# setting: run the statusLine command from the settings as Claude Code does,
# in the project, with Claude Code's JSON on stdin.
setting() {
  local cmd
  cmd=$(jq -r '.statusLine.command' "$SETTINGS")
  run sh -c "$cmd" < "$TEST_ROOT/cc.json"
}

# got_input: the earlier status line received the same JSON Claude Code sent.
got_input() {
  [ -f "$HOME/mine.input" ] || {
    echo "the earlier status line did not run"
    false
  }
  jq -e --slurpfile a "$TEST_ROOT/cc.json" '. == $a[0]' "$HOME/mine.input" > /dev/null || {
    echo "the earlier status line got other input:"
    cat "$HOME/mine.input"
    false
  }
}

@test "R184: where VBW is off, the setting shows the user's earlier status line, given Claude Code's own input" {
  settings_with "$(mine)" '{"theme": "dark"}'
  vbw_run statusline on
  [ "$status" -eq 0 ]
  [[ "$output" == *"replaced yours, which is saved"* ]]
  installed off
  setting
  [ "$status" -eq 0 ] && [ "$output" = "my own line 1" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output"
    false
  }
  got_input
}

@test "R184: where VBW is off and there was no earlier status line, the setting shows nothing" {
  vbw_run statusline on
  [ "$status" -eq 0 ]
  installed off
  setting
  [ "$status" -eq 0 ] && [ -z "$output" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output"
    false
  }
}

@test "R184: where VBW is on, the setting shows VBW's lines only and never runs the earlier status line" {
  settings_with "$(mine)"
  vbw_run statusline on
  installed on
  setting
  [ "$status" -eq 0 ] && [ "$output" = "[VBW] stand-in" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output"
    false
  }
  [ ! -e "$HOME/mine.input" ]
}

@test "R184: with no input and stdin left open, the setting does not hang" {
  settings_with "$(mine)"
  vbw_run statusline on
  installed off
  local cmd pid i=0
  cmd=$(jq -r '.statusLine.command' "$SETTINGS")
  # A watchdog, not a clock: the setting must end on its own within about 5 s (50 looks, 0.1 s apart).
  sh -c "$cmd" < <(exec 3>&-; sleep 8) > "$TEST_ROOT/out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2> /dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2> /dev/null; then
    kill "$pid" 2> /dev/null
    echo "the setting was still waiting for input that never came after about 5 s"
    false
  fi
  wait "$pid" || true
  [ "$(cat "$TEST_ROOT/out")" = "my own line 1" ]
}

@test "R184: vbw statusline on updates an older VBW setting in place, keeping the refresh interval, every other field and the saved earlier status line" {
  settings_with "$(jq -nc --arg c "$OLD_CMD" '{type: "command", command: $c, refreshInterval: 10, padding: 2}')" '{"theme": "dark"}'
  mine > "$BACKUP"
  cp "$BACKUP" "$TEST_ROOT/backup.before"
  vbw_run statusline on
  [ "$status" -eq 0 ]
  jq -e --arg old "$OLD_CMD" '.theme == "dark" and .statusLine.type == "command" and .statusLine.command != $old
    and (.statusLine.command | contains("vbw-statusline.sh"))
    and .statusLine.refreshInterval == 10 and .statusLine.padding == 2' "$SETTINGS" || {
    cat "$SETTINGS"
    false
  }
  cmp "$BACKUP" "$TEST_ROOT/backup.before"
  installed off
  setting
  [ "$output" = "my own line 1" ]
  got_input
  vbw_run statusline status
  [ "$output" = "on: the VBW status line" ]
  # Run again, it changes nothing.
  cp "$SETTINGS" "$TEST_ROOT/settings.once"
  vbw_run statusline on
  [ "$output" = "on: the VBW status line" ]
  cmp "$SETTINGS" "$TEST_ROOT/settings.once"
}

@test "R184: vbw statusline off still brings back the earlier status line exactly, or removes VBW's when there was none" {
  settings_with "$(jq -nc --arg c "$MINE_CMD" '{type: "command", command: $c, padding: 3}')" '{"theme": "dark"}'
  vbw_run statusline on
  vbw_run statusline status
  [ "$output" = "on: the VBW status line" ]
  vbw_run statusline off
  [[ "$output" == *"your previous status line is back"* ]]
  jq -e --arg c "$MINE_CMD" '.theme == "dark" and .statusLine == {type: "command", command: $c, padding: 3}' "$SETTINGS"
  [ ! -e "$BACKUP" ]
  printf '{"theme": "dark"}\n' > "$SETTINGS"
  vbw_run statusline on
  vbw_run statusline off
  jq -e '.theme == "dark" and (has("statusLine") | not)' "$SETTINGS"
}

@test "R184: vbw doctor flags an older VBW setting with vbw statusline on as the fix, and not once it is updated" {
  settings_with "$(jq -nc --arg c "$OLD_CMD" '{type: "command", command: $c, refreshInterval: 5}')"
  run "$VBW" doctor
  printf '%s\n' "$output" | grep -A1 -E '^! .*status line' | grep -qx '    fix: vbw statusline on' || {
    echo "doctor does not flag the older setting:"
    printf '%s\n' "$output"
    false
  }
  vbw_run statusline on
  run "$VBW" doctor
  printf '%s\n' "$output" | grep -qx '✓ VBW status line'
  if printf '%s\n' "$output" | grep -qE '^! .*status line'; then
    echo "doctor still flags the updated setting:"
    printf '%s\n' "$output"
    false
  fi
}

@test "R184: a session that starts in a VBW project updates an older VBW setting, keeping its interval and the saved earlier status line" {
  "$VBW" init > /dev/null
  settings_with "$(jq -nc --arg c "$OLD_CMD" '{type: "command", command: $c, refreshInterval: 10}')"
  mine > "$BACKUP"
  cp "$BACKUP" "$TEST_ROOT/backup.before"
  CLAUDE_PROJECT_DIR="$PROJECT" bash "$PLUGIN_ROOT/hooks/session-start.sh" < /dev/null > /dev/null
  jq -e --arg old "$OLD_CMD" '.statusLine.command != $old and (.statusLine.command | contains("vbw-statusline.sh"))
    and .statusLine.refreshInterval == 10' "$SETTINGS" || {
    cat "$SETTINGS"
    false
  }
  cmp "$BACKUP" "$TEST_ROOT/backup.before"
  installed off
  setting
  [ "$output" = "my own line 1" ]
}
