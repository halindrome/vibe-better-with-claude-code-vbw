#!/usr/bin/env bats
# R185 (F220), R152 (docs/proof.md): a SessionStart hook input pipe that stays
# open does not delay session start, measured in the release run
# (tests/timed-*.bats), never in vbw prove, because it times the hook in
# milliseconds. The session of a --plugin-dir copy is still recorded.

load helper

setup() {
  vbw_setup
  mkdir -p "$TEST_ROOT/session"
  export CLAUDE_ENV_FILE="$TEST_ROOT/session/env.sh"
}

teardown() { vbw_teardown; }

# loaded: the plugin data folder Claude Code gives the hooks of a copy loaded with --plugin-dir.
loaded() { export CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugins/data/vbw-inline"; }

@test "R185: a hook input pipe that stays open does not delay session start, and the session is still recorded" {
  vbw_git_project
  "$VBW" init > /dev/null
  loaded
  local cmd ms
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json")
  ms=$({
    printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"s1"}\n'
    sleep 3
  } | {
    t0=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$PROJECT" sh -c "$cmd" > /dev/null
    t1=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
    echo $((t1 - t0))
  })
  [ "$ms" -lt 800 ] || {
    echo "the hook took $ms ms with the input pipe left open"
    false
  }
  [ "$(cat "$CLAUDE_CONFIG_DIR/vbw/sessions/s1")" = "$PLUGIN_ROOT" ]
  grep -q "$PLUGIN_ROOT/bin" "$CLAUDE_ENV_FILE"
}
