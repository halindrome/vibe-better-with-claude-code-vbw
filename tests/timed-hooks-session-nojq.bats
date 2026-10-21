#!/usr/bin/env bats
# R141, R152 (docs/proof.md): the time of the session-start hook without jq,
# measured in the release run (tests/timed-*.bats), never in vbw prove: five
# session starts finish within 3 s. PATH setup as in tests/hooks-session-nojq.bats.

load helper

# The SessionStart command exactly as hooks.json gives it (JSON-escaped quotes).
HOOK_CMD='bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"'

setup() {
  vbw_setup
  vbw_git_project
  STUB="$TEST_ROOT/plugin"
  MARK="$TEST_ROOT/kernel-ran"
  NOJQ="$TEST_ROOT/nojq-bin"
  export STUB MARK NOJQ
  mkdir -p "$STUB/hooks" "$STUB/bin" "$NOJQ"
  cp "$PLUGIN_ROOT/hooks/hooks.json" "$PLUGIN_ROOT/hooks/session-start.sh" "$STUB/hooks/"
  cat > "$STUB/bin/vbw" << EOF
#!/usr/bin/env bash
: > "$MARK"
echo "stand-in kernel ran: \$*" >&2
exit 1
EOF
  chmod +x "$STUB/bin/vbw"
  local t p
  for t in bash sh git awk head rm rmdir; do
    p=$(command -v "$t") || {
      echo "host has no $t"
      return 1
    }
    ln -s "$p" "$NOJQ/$t"
  done
  # Folders: a VBW project root, one made by a newer VBW, a VBW 1 plan, a
  # subfolder of a VBW project, and a folder that is not a VBW project.
  mkdir -p .vbw src
  printf '{"schema": 1}\n' > .vbw/record.json
  NEWER="$TEST_ROOT/newer"
  V1="$TEST_ROOT/v1 plan"
  PLAIN="$TEST_ROOT/plain"
  export NEWER V1 PLAIN
  mkdir -p "$NEWER/.vbw" "$V1/.vbw-planning" "$PLAIN"
  printf '{"schema": 99}\n' > "$NEWER/.vbw/record.json"
}

teardown() { vbw_teardown; }

# no_jq_start DIR: run the hooks.json SessionStart command for DIR the way Claude
# Code does (sh -c, hook input on stdin), with PATH holding no jq. Sets status,
# output (stdout) and ERR (stderr).
no_jq_start() {
  local err="$TEST_ROOT/stderr"
  status=0
  output=$(env PATH="$NOJQ" CLAUDE_PLUGIN_ROOT="$STUB" CLAUDE_PROJECT_DIR="$1" \
    "$NOJQ/sh" -c "$HOOK_CMD" 2> "$err" <<< '{"hook_event_name": "SessionStart", "source": "startup"}') || status=$?
  ERR=$(cat "$err")
}

# quiet DIR: the hook ends with exit 0, no stdout, no stderr and no kernel run.
quiet() {
  rm -f "$MARK"
  no_jq_start "$1"
  [ "$status" -eq 0 ] || {
    echo "$1: exit $status; stderr: $ERR"
    return 1
  }
  [ -z "$output" ] || {
    echo "$1: stdout: $output"
    return 1
  }
  [ -z "$ERR" ] || {
    echo "$1: stderr: $ERR"
    return 1
  }
  [ ! -e "$MARK" ] || {
    echo "$1: the hook ran a kernel command"
    return 1
  }
}

@test "R141: without jq, the hook stops early: five starts finish well within the hook time budget" {
  local d start
  start=$SECONDS
  for d in "$PROJECT" "$NEWER" "$V1" "$PROJECT/src" "$PLAIN"; do
    quiet "$d"
  done
  [ $((SECONDS - start)) -le 3 ] || {
    echo "five starts took $((SECONDS - start)) s"
    false
  }
}
