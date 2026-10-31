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

@test "R184: the setting starts one bash, whether VBW is off or on: the installed script runs inside it" {
  local real
  real=$(command -v bash)
  mkdir -p "$TEST_ROOT/count"
  printf '#!/bin/sh\necho x >> "%s/calls"\nexec "%s" "$@"\n' "$TEST_ROOT/count" "$real" > "$TEST_ROOT/count/bash"
  chmod +x "$TEST_ROOT/count/bash"
  settings_with "$(mine)"
  vbw_run statusline on
  local cmd mode n
  cmd=$(jq -r '.statusLine.command' "$SETTINGS")
  for mode in off on; do
    installed "$mode"
    rm -f "$TEST_ROOT/count/calls" "$HOME/mine.input"
    PATH="$TEST_ROOT/count:$PATH" sh -c "$cmd" < "$TEST_ROOT/cc.json" > /dev/null
    # Where VBW is off the earlier status line is a bash script of its own (MINE_CMD): that one is not VBW's.
    n=$(wc -l < "$TEST_ROOT/count/calls" | tr -d ' ')
    case "$mode" in off) [ "$n" = 2 ] ;; on) [ "$n" = 1 ] ;; esac || {
      echo "VBW $mode: $n bash processes started"
      cat "$TEST_ROOT/count/calls"
      false
    }
  done
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

@test "R184: vbw statusline on keeps the earlier status line's padding and its own refresh interval in the setting" {
  settings_with "$(jq -nc --arg c "$MINE_CMD" '{type: "command", command: $c, padding: 2, refreshInterval: 30}')" '{"theme": "dark"}'
  vbw_run statusline on
  [ "$status" -eq 0 ]
  jq -e '.theme == "dark" and .statusLine.type == "command" and (.statusLine.command | contains("vbw-statusline.sh"))
    and .statusLine.padding == 2 and .statusLine.refreshInterval == 30' "$SETTINGS" || {
    cat "$SETTINGS"
    false
  }
  # An earlier line with neither: VBW's 5 seconds, and no padding is invented.
  settings_with "$(jq -nc --arg c "$MINE_CMD" '{type: "command", command: $c}')"
  rm -f "$BACKUP"
  vbw_run statusline on
  jq -e '.statusLine.refreshInterval == 5 and (.statusLine | has("padding") | not)' "$SETTINGS" || {
    cat "$SETTINGS"
    false
  }
  # Off brings back exactly what was there.
  vbw_run statusline off
  jq -e --arg c "$MINE_CMD" '.statusLine == {type: "command", command: $c}' "$SETTINGS"
}

@test "R184: vbw statusline on gives an older VBW setting the saved earlier status line's padding when it has none, and a padding set there stays" {
  settings_with "$(jq -nc --arg c "$OLD_CMD" '{type: "command", command: $c, refreshInterval: 5}')"
  jq -nc --arg c "$MINE_CMD" '{type: "command", command: $c, padding: 3}' > "$BACKUP"
  vbw_run statusline on
  jq -e '.statusLine.padding == 3 and .statusLine.refreshInterval == 5' "$SETTINGS" || {
    cat "$SETTINGS"
    false
  }
  cp "$SETTINGS" "$TEST_ROOT/settings.once"
  vbw_run statusline on
  cmp "$SETTINGS" "$TEST_ROOT/settings.once"
  jq '.statusLine.padding = 1' "$SETTINGS" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$SETTINGS"
  vbw_run statusline on
  jq -e '.statusLine.padding == 1' "$SETTINGS"
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

# R224 (#692): outside a VBW project (no .vbw folder at or above the folder Claude Code
# reports, else the one the script runs in) the installed script prints nothing and exits
# 3, and the setting's hand-back path then runs the earlier status line with Claude Code's
# own input, its output printed unchanged; with none saved, nothing at all shows. The
# setting written by an earlier 2.1.x needs no rewrite: it already honours exit 3.

# The setting `vbw statusline on` wrote in 2.1.19 with `sh "$HOME/mine.sh"` saved as the
# earlier status line, byte for byte.
SETTING_2_1_19='bash -c '"'"'i=; while IFS= read -t 1 -r l; do i=$i$l$'"'"'\'"'"''"'"'\n'"'"'\'"'"''"'"'; done; [ -z "$l" ] || i=$i$l; rc=0; sid=; _s=; for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; f=; p=; if [ -z "$_s" ] && [ -d "$_d/vbw/sessions" ]; then _s=1; sid=$(printf %s "$i" | jq -r '"'"'\'"'"''"'"'.session_id // empty'"'"'\'"'"''"'"' 2>/dev/null); case "$sid" in *[!A-Za-z0-9_-]*) sid= ;; esac; fi; [ -z "$sid" ] || { read -r p < "$_d/vbw/sessions/$sid"; } 2>/dev/null || p=; if [ -n "$p" ] && [ -f "$p/.claude-plugin/plugin.json" ] && [ -f "$p/scripts/vbw-statusline.sh" ]; then f=$p/scripts/vbw-statusline.sh; else set -- "$_d"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh; if [ $# -eq 1 ]; then f=$1; else f=$(ls -1 "$@" 2>/dev/null | sort -V | tail -1 || true); fi; fi; if [ -f "$f" ]; then printf %s "$i" | { . "$f"; }; rc=$?; [ "$rc" -eq 3 ] && break; exit "$rc"; fi; done; [ "$rc" -eq 3 ] && printf %s "$i" | sh -c '"'"'\'"'"''"'"'sh "$HOME/mine.sh"'"'"'\'"'"''"'"'; exit 0'"'"' vbw'

# installed_real: the setting runs the plugin under test (the session's record names it, R185).
installed_real() {
  mkdir -p "$CLAUDE_CONFIG_DIR/vbw/sessions"
  printf '%s\n' "$PLUGIN_ROOT" > "$CLAUDE_CONFIG_DIR/vbw/sessions/s1"
}

# outside: OUT is a folder with no .vbw at or above it (and no .git); Claude Code's input
# names it. A .vbw above the test root would make the test prove nothing, so it is refused.
outside() {
  local d="$TEST_ROOT"
  while [ "$d" != / ] && [ -n "$d" ]; do
    [ ! -d "$d/.vbw" ] || { echo "a .vbw folder sits above the test root: $d"; return 1; }
    d=${d%/*}
  done
  OUT="$TEST_ROOT/elsewhere"
  mkdir -p "$OUT"
  jq -nc --arg d "$OUT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, cwd: $d,
    model: {display_name: "Sonnet 5.5"}, version: "2.1.286", cost: {total_cost_usd: 1.25}}' > "$TEST_ROOT/cc.json"
}

# setting_in DIR: run the statusLine command from the settings as Claude Code does, in DIR.
setting_in() {
  local cmd
  cmd=$(jq -r '.statusLine.command' "$SETTINGS")
  run sh -c "cd \"\$1\" && $cmd" _ "$1" < "$TEST_ROOT/cc.json"
}

# two_lines: the earlier status line prints two lines with colour codes and keeps its input.
two_lines() {
  printf '#!/bin/sh\ncat > "$HOME/mine.input"\nprintf "\\033[32mline one\\033[0m\\nline two \\033[1m$MY_LINE\\033[0m\\n"\n' > "$HOME/it's my line.sh"
}

@test "R224: outside a VBW project the setting shows the user's earlier status line unchanged, several lines and colour codes included, given Claude Code's own input" {
  two_lines
  settings_with "$(mine)"
  vbw_run statusline on
  [ "$status" -eq 0 ]
  installed_real
  outside
  setting_in "$OUT"
  [ "$status" -eq 0 ] && [ "$output" = "$(printf '\033[32mline one\033[0m\nline two \033[1m1\033[0m')" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output" | cat -v
    false
  }
  got_input
}

@test "R224: outside a VBW project with no earlier status line, the setting shows nothing at all: no 'no project here' line, and no VBW 1 line for a .vbw-planning folder" {
  vbw_run statusline on
  installed_real
  outside
  mkdir -p "$OUT/.vbw-planning"
  setting_in "$OUT"
  [ "$status" -eq 0 ] && [ -z "$output" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output"
    false
  }
}

@test "R224: the script judges by the folder Claude Code reports, else the one it runs in: no input from an outside folder exits 3; an outside folder with a project named in the input renders as today" {
  outside
  cd "$OUT"
  # Nothing on stdin: the folder it runs in decides (tests/statusline.bats pins the plain outside render).
  run bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" < /dev/null
  [ "$status" -eq 3 ] && [ -z "$output" ] || { echo "exit $status, output:"; printf '%s\n' "$output"; false; }
  # Inside a VBW project, from a folder outside it: the folder Claude Code reports wins.
  cd "$PROJECT" && "$VBW" init > /dev/null
  cd "$OUT"
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, cwd: $d, model: {display_name: "Sonnet 5.5"}}' > "$TEST_ROOT/inside.json"
  NO_COLOR=1 run bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" < "$TEST_ROOT/inside.json"
  [ "$status" -eq 0 ] && [[ "${lines[0]}" == "[VBW] project with space │"* ]] || { echo "exit $status, output:"; printf '%s\n' "$output"; false; }
}

@test "R224: a setting written by 2.1.19, its text unchanged, hands back outside a VBW project: no rewrite is needed" {
  printf '#!/bin/sh\necho "mine from 2.1.19"\n' > "$HOME/mine.sh"
  settings_with "$(jq -nc --arg c "$SETTING_2_1_19" '{type: "command", command: $c, refreshInterval: 5}')"
  installed_real
  outside
  setting_in "$OUT"
  [ "$status" -eq 0 ] && [ "$output" = "mine from 2.1.19" ] || {
    echo "exit $status, output:"
    printf '%s\n' "$output"
    false
  }
}

@test "R224 docs: docs/statusline.md says exit 3 hands back both where VBW is turned off and where there is no VBW project, and no longer shows the no-project line as what is shown outside a project" {
  local doc="$REPO_ROOT/docs/statusline.md"
  tr '\n' ' ' < "$doc" | tr -s ' ' | grep -qiE 'exit 3[^.]*(no vbw project|outside a vbw project|not (part of|in) a vbw project)|(no vbw project|outside a vbw project)[^.]*exit 3' || {
    echo "docs/statusline.md does not say exit 3 is the hand-back where there is no VBW project"
    false
  }
  tr '\n' ' ' < "$doc" | tr -s ' ' | grep -qiE 'exit 3[^.]*turned off|turned off[^.]*exit 3' || {
    echo "docs/statusline.md does not say exit 3 is the hand-back where VBW is turned off"
    false
  }
  ! grep -qF 'no project here' "$doc" || { echo "docs/statusline.md still shows the no-project line"; false; }
}
