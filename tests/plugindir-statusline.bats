#!/usr/bin/env bats
# R185: the status line of a session that loaded VBW from a working tree
# (claude --plugin-dir) is rendered by that tree's status line script and
# shows the tree's version. The statusLine setting is user-wide, so the choice
# is the session's alone: the loaded copy's SessionStart hook records it for
# its session id, and the setting reads Claude Code's session_id. A later
# normal session, the same session resumed without the tree, and a tree that
# was moved, deleted or is no VBW plugin any more all show the installed copy,
# never a failure. A project that turns the installed VBW off still shows VBW
# when the tree is loaded (the loaded copy is on), and without the tree it
# still hands back (R184). The session start writes only to the project's
# .vbw/runtime, VBW's folder in the Claude config folder and the env file, and
# the status line runs no git process. L1: the installed release and the
# working tree are copies of the plugin under test with versions 9.9.9 and
# 7.7.7; the setting is run with sh -c, as Claude Code runs it.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  INST="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.9"
  TREE="$TEST_ROOT/dev tree/plugin"
  copy "$INST" 9.9.9 installed
  copy "$TREE" 7.7.7 tree
  SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
  "$TREE/bin/vbw" statusline on > /dev/null
  mkdir -p "$TEST_ROOT/session"
  : > "$TEST_ROOT/ran"
}

teardown() { vbw_teardown; }

# copy DIR VERSION NAME: the plugin under test at DIR with VERSION; its status
# line script notes NAME in $TEST_ROOT/ran each time it runs.
copy() {
  mkdir -p "$(dirname "$1")"
  cp -R "$PLUGIN_ROOT" "$1"
  jq --arg v "$2" '.version = $v' "$PLUGIN_ROOT/.claude-plugin/plugin.json" > "$1/.claude-plugin/plugin.json"
  local sl="$1/scripts/vbw-statusline.sh"
  {
    sed -n 1p "$PLUGIN_ROOT/scripts/vbw-statusline.sh"
    printf 'printf "%%s\\n" %s >> "$TEST_ROOT/ran"\n' "$3"
    sed -n '2,$p' "$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  } > "$sl"
}

# start ROOT DATA_ID SID: the SessionStart hook of the copy at ROOT starts
# session SID; DATA_ID is the plugin data folder Claude Code gives its hooks
# (vbw-inline for a copy loaded with --plugin-dir, vbw-vbw-marketplace for the
# installed one).
start() {
  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$1/hooks/hooks.json")
  jq -nc --arg d "$PROJECT" --arg s "$3" '{hook_event_name: "SessionStart", source: "startup", session_id: $s, cwd: $d}' \
    | CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$PROJECT" CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugins/data/$2" \
      CLAUDE_ENV_FILE="$TEST_ROOT/session/env.sh" sh -c "$cmd" > /dev/null
}
loaded_session() { start "$TREE" vbw-inline "$1"; }
installed_session() { start "$INST" vbw-vbw-marketplace "$1"; }

# render SID: the statusLine setting run as Claude Code runs it, for session SID.
render() {
  local cmd
  cmd=$(jq -r '.statusLine.command' "$SETTINGS")
  : > "$TEST_ROOT/ran"
  jq -nc --arg d "$PROJECT" --arg s "$1" '{session_id: $s, workspace: {project_dir: $d, current_dir: $d}, cwd: $d,
    model: {display_name: "Sonnet 5.5"}, version: "2.1.296"}' > "$TEST_ROOT/cc.json"
  run env NO_COLOR=1 sh -c "$cmd" < "$TEST_ROOT/cc.json"
}

# shows VERSION SCRIPT: the render passed, shows VBW VERSION, and only SCRIPT's
# status line script ran.
shows() {
  [ "$status" -eq 0 ] || {
    echo "the status line failed ($status): $output"
    false
  }
  [[ "$output" == *"VBW $1"* ]] || {
    echo "the status line does not show VBW $1:"
    printf '%s\n' "$output"
    false
  }
  [ "$(LC_ALL=C sort -u "$TEST_ROOT/ran")" = "$2" ] || {
    echo "expected only the $2 script to render; ran: $(tr '\n' ' ' < "$TEST_ROOT/ran")"
    false
  }
}

@test "R185: a session that loaded a working tree shows the tree's version, rendered by the tree's own script" {
  loaded_session s1
  render s1
  shows 7.7.7 tree
}

@test "R185: in a normal installed session the status line shows the newest installed version, as before" {
  installed_session s2
  render s2
  shows 9.9.9 installed
}

@test "R185: the choice never leaks: a later normal session, and the same session resumed without the tree, show the installed copy" {
  loaded_session s1
  render s2
  shows 9.9.9 installed
  installed_session s1
  render s1
  shows 9.9.9 installed
}

@test "R185: a working tree that was moved or deleted falls back to the installed copy instead of failing" {
  loaded_session s1
  mv "$TEST_ROOT/dev tree" "$TEST_ROOT/moved tree"
  render s1
  shows 9.9.9 installed
  rm -rf "$TEST_ROOT/moved tree"
  render s1
  shows 9.9.9 installed
}

@test "R185: a recorded folder that is no VBW plugin any more is never run: the installed copy renders" {
  loaded_session s1
  rm -f "$TREE/.claude-plugin/plugin.json"
  render s1
  shows 9.9.9 installed
}

@test "R185: with the installed VBW turned off for the project, a session that loaded the tree still shows VBW, and one without it still hands back" {
  mkdir -p .claude
  jq -n '{enabledPlugins: {"vbw@vbw-marketplace": false}}' > .claude/settings.json
  loaded_session s1
  render s1
  shows 7.7.7 tree
  # No --plugin-dir: VBW is off there and no earlier status line was saved, so nothing shows (R184).
  render s2
  [ "$status" -eq 0 ]
  [ -z "$output" ] || {
    echo "VBW showed where it is off: $output"
    false
  }
}

@test "R185: the session start writes only to the project's runtime folder, VBW's Claude config folder and the env file, whatever the session id" {
  local sid
  for sid in s1 '../../outside' 'a/b'; do
    touch "$TEST_ROOT/before"
    sleep 1
    loaded_session "$sid"
    local f bad=""
    while IFS= read -r f; do
      case "$f" in
        "$PROJECT/.vbw/runtime/"* | "$CLAUDE_CONFIG_DIR/vbw/"* | "$TEST_ROOT/session/env.sh" | "$TEST_ROOT/ran") ;;
        *) bad="$bad $f" ;;
      esac
    done < <(find "$TEST_ROOT" -newer "$TEST_ROOT/before" -type f ! -path '*/.git/*')
    [ -z "$bad" ] || {
      echo "session $sid wrote outside the allowed places:$bad"
      false
    }
  done
  # A session id that is not a plain name is never followed: the installed copy renders it.
  render '../../outside'
  shows 9.9.9 installed
}

@test "R185: the status line of a loaded tree runs no git process" {
  mkdir -p "$TEST_ROOT/stubs"
  printf '#!/bin/sh\necho "$*" >> "%s/git.log"\nexit 1\n' "$TEST_ROOT" > "$TEST_ROOT/stubs/git"
  chmod +x "$TEST_ROOT/stubs/git"
  loaded_session s1
  PATH="$TEST_ROOT/stubs:$PATH" render s1
  shows 7.7.7 tree
  [ ! -s "$TEST_ROOT/git.log" ] || {
    echo "git ran: $(cat "$TEST_ROOT/git.log")"
    false
  }
}
