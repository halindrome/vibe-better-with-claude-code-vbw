#!/usr/bin/env bats
# R185: vbw --version prints the version of the plugin the kernel belongs to,
# like vbw version. vbw doctor shows which vbw is on PATH (its path and
# version) and which plugin is loaded, and warns with the fix when they differ.
# The loaded plugin is the one the session's SessionStart hook recorded for
# its session (CLAUDE_CODE_SESSION_ID, as Claude Code sets it for the Bash
# tool), else the plugin of the kernel running doctor (/vbw:doctor runs the
# loaded plugin's own kernel). L1: the installed release is a stand-in kernel
# in a plugin cache under the test's Claude config folder; the loaded copy is
# the plugin under test, started the way claude --plugin-dir starts it.

load helper

setup() {
  vbw_setup
  vbw_git_project
  INST="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.9"
  mkdir -p "$INST/bin"
  cat > "$INST/bin/vbw" << 'EOF'
#!/bin/sh
case "${1:-}" in
  version | --version) echo 9.9.9 ;;
  *) echo "vbw: installed stand-in" >&2; exit 1 ;;
esac
EOF
  chmod +x "$INST/bin/vbw"
  mkdir -p "$INST/.claude-plugin"
  printf '{"name": "vbw", "version": "9.9.9"}\n' > "$INST/.claude-plugin/plugin.json"
  TREE_VERSION=$(jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  # The host may have VBW on PATH (a test run from inside a Claude Code
  # session): start from a PATH without any vbw.
  CLEAN_PATH=""
  local p
  while IFS= read -r p; do
    [ -n "$p" ] && [ ! -x "$p/vbw" ] && CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$p"
  done < <(printf '%s\n' "$PATH" | tr ':' '\n')
  export PATH="$CLEAN_PATH"
  unset CLAUDE_CODE_SESSION_ID
}

teardown() { vbw_teardown; }

# loaded_session SID: the plugin under test starts session SID as a copy
# loaded with --plugin-dir (Claude Code names it vbw@inline, so its hooks get a
# plugin data folder named vbw-inline).
loaded_session() {
  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json")
  mkdir -p "$TEST_ROOT/session"
  jq -nc --arg d "$PROJECT" --arg s "$1" '{hook_event_name: "SessionStart", source: "startup", session_id: $s, cwd: $d}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$PROJECT" CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugins/data/vbw-inline" \
      CLAUDE_ENV_FILE="$TEST_ROOT/session/env.sh" sh -c "$cmd" > /dev/null
}

# doctor_lines MARK: doctor's lines that start with MARK (✓ ok, ! warn), each
# followed by its fix line when it has one.
doctor_lines() {
  printf '%s\n' "$output" | awk -v m="$1" 'index($0, m " ") == 1 { keep = 1; print; next } /^    fix: / && keep { print; next } { keep = 0 }'
}

@test "R185: vbw --version prints the plugin's version, as vbw version does, in and outside a project" {
  run "$VBW" --version < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "$TREE_VERSION" ]
  cd "$TEST_ROOT"
  run "$VBW" --version < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "$TREE_VERSION" ]
  [ "$("$VBW" version)" = "$output" ]
}

@test "R185: vbw doctor says the vbw on PATH is the loaded plugin's, with its path and version" {
  loaded_session s1
  PATH="$PLUGIN_ROOT/bin:$PATH" CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  local ok
  ok=$(doctor_lines "✓")
  printf '%s\n' "$ok" | grep -F "$PLUGIN_ROOT/bin/vbw" | grep -qF "$TREE_VERSION" || {
    echo "no ok line names $PLUGIN_ROOT/bin/vbw and version $TREE_VERSION:"
    printf '%s\n' "$output"
    false
  }
  if printf '%s\n' "$output" | grep -E '^! ' | grep -qF "$INST"; then
    echo "a warning names the installed release:"
    printf '%s\n' "$output"
    false
  fi
}

@test "R185: in a session that loaded a working tree, an installed release first on PATH is a warning, with the fix naming the loaded kernel" {
  loaded_session s1
  PATH="$INST/bin:$PLUGIN_ROOT/bin:$PATH" CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  local warn
  warn=$(doctor_lines "!")
  printf '%s\n' "$warn" | grep -E '^! ' | grep -F "$INST/bin/vbw" | grep -qF "$PLUGIN_ROOT" || {
    echo "no warning names both the vbw on PATH ($INST/bin/vbw) and the loaded plugin ($PLUGIN_ROOT):"
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$warn" | grep -E '^    fix: ' | grep -qF "$PLUGIN_ROOT/bin/vbw" || {
    echo "no fix names $PLUGIN_ROOT/bin/vbw:"
    printf '%s\n' "$output"
    false
  }
  # The version of each is shown.
  printf '%s\n' "$warn" | grep -qF 9.9.9
}

@test "R185: with no session recorded, the loaded plugin is the one running doctor, and a different vbw on PATH is a warning" {
  PATH="$INST/bin:$PATH" run "$VBW" doctor < /dev/null
  local warn
  warn=$(doctor_lines "!")
  printf '%s\n' "$warn" | grep -E '^! ' | grep -F "$INST/bin/vbw" | grep -qF "$PLUGIN_ROOT" || {
    echo "no warning names both $INST/bin/vbw and $PLUGIN_ROOT:"
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$warn" | grep -E '^    fix: ' | grep -qF "$PLUGIN_ROOT/bin/vbw"
}

@test "R185: no vbw on PATH at all is a warning too, with the fix naming the loaded kernel" {
  loaded_session s1
  CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  local warn
  warn=$(doctor_lines "!")
  printf '%s\n' "$warn" | grep -E '^! ' | grep -F 'PATH' | grep -qF 'vbw' || {
    echo "no warning about vbw missing from PATH:"
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$warn" | grep -E '^    fix: ' | grep -qF "$PLUGIN_ROOT/bin/vbw"
}
