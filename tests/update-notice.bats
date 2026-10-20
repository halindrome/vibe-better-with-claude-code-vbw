#!/usr/bin/env bats
# T136 (docs/update.md): after VBW has been updated, the first session in a VBW
# project offers /vbw:whats-new once. No network: the version the running plugin
# has is compared with the highest version this clone's sessions have seen, kept in
# $(git-common-dir)/vbw/seen-version. The offer is the SessionStart hook's
# systemMessage (the user sees it at once) with a matching line of context. L1: the
# real hook script, in a copy of the plugin whose version the test chooses.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  SEEN="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/seen-version"
  PLUG="$TEST_ROOT/plug"
}

teardown() { vbw_teardown; }

# plugin_version V: the plugin the hook runs from, at version V. Only the hook and
# a kernel that hands every call to the real one.
plugin_version() {
  mkdir -p "$PLUG/hooks" "$PLUG/bin" "$PLUG/.claude-plugin"
  cp "$PLUGIN_ROOT/hooks/session-start.sh" "$PLUG/hooks/"
  printf '{"name": "vbw", "version": "%s"}\n' "$1" > "$PLUG/.claude-plugin/plugin.json"
  printf '#!/usr/bin/env bash\nexec "%s/bin/vbw" "$@"\n' "$PLUGIN_ROOT" > "$PLUG/bin/vbw"
  chmod +x "$PLUG/bin/vbw"
}

# session_start [DIR]: one SessionStart of the plugin copy, as an installed copy
# (the plugin data folder of vbw@vbw-marketplace) in DIR (default: the project).
session_start() {
  printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"s1"}\n' \
    | CLAUDE_PLUGIN_ROOT="$PLUG" CLAUDE_PLUGIN_DATA="${DATA:-$TEST_ROOT/plugins/data/vbw-vbw-marketplace}" \
      CLAUDE_PROJECT_DIR="${1:-$PROJECT}" bash "$PLUG/hooks/session-start.sh"
}

notice() { printf '%s' "$1" | jq -r '.systemMessage // ""'; }
context() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""'; }

@test "T136: the first session in a clone records the version and offers nothing" {
  plugin_version 2.0.41
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [[ "$(context "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.41" ]
}

@test "T136: after an update the first session names both versions and /vbw:whats-new, to the user and in the context" {
  plugin_version 2.0.41
  mkdir -p "${SEEN%/*}" && printf '2.0.40\n' > "$SEEN"
  run session_start
  [ "$status" -eq 0 ]
  [ "$(notice "$output")" = "VBW updated from 2.0.40 to 2.0.41. /vbw:whats-new shows what changed." ] || { echo "$output"; false; }
  [[ "$(context "$output")" == *"VBW project ("* ]]
  [[ "$(context "$output")" == *"updated from 2.0.40 to 2.0.41"* && "$(context "$output")" == *"do not repeat"* ]] || { context "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.41" ]
}

@test "T136: the offer shows once, however many sessions follow" {
  plugin_version 2.0.41
  mkdir -p "${SEEN%/*}" && printf '2.0.40\n' > "$SEEN"
  run session_start
  [[ "$(notice "$output")" == *"whats-new"* ]]
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [[ "$(context "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
}

@test "T136: versions compare as numbers: a seen 2.0.100 is newer than 2.0.41, and 2.0.9 is older" {
  plugin_version 2.0.41
  mkdir -p "${SEEN%/*}" && printf '2.0.100\n' > "$SEEN"
  run session_start
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.100" ]
  printf '2.0.9\n' > "$SEEN"
  run session_start
  [[ "$(notice "$output")" == *"updated from 2.0.9 to 2.0.41"* ]] || { echo "$output"; false; }
}

@test "T136: an older plugin offers nothing and the highest version seen stays, so coming back to the newer one offers nothing either" {
  plugin_version 2.0.40
  mkdir -p "${SEEN%/*}" && printf '2.0.41\n' > "$SEEN"
  run session_start
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.41" ]
  plugin_version 2.0.41
  run session_start
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
}

@test "T136: a copy loaded with --plugin-dir neither offers nor records" {
  plugin_version 2.0.41
  mkdir -p "${SEEN%/*}" && printf '2.0.40\n' > "$SEEN"
  DATA="$TEST_ROOT/plugins/data/vbw-inline" run session_start
  [ "$status" -eq 0 ]
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.40" ]
  rm -f "$SEEN"
  DATA="$TEST_ROOT/plugins/data/vbw-inline" run session_start
  [ ! -e "$SEEN" ]
}

@test "T136: a seen file that holds no version counts as unseen: nothing offered, then rewritten" {
  plugin_version 2.0.41
  mkdir -p "${SEEN%/*}" && printf 'garbage\n' > "$SEEN"
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.41" ]
}

@test "T136: outside a VBW project the hook offers nothing and writes nothing" {
  plugin_version 2.0.41
  rm -rf .vbw
  mkdir -p "${SEEN%/*}" && printf '2.0.40\n' > "$SEEN"
  run session_start
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$SEEN")" = "2.0.40" ]
  rm -rf "${SEEN%/*}"
  run session_start
  [ ! -e "${SEEN%/*}" ]
}

@test "T136: a project made by a newer VBW is told to update, with no offer and no record" {
  plugin_version 2.0.41
  jq '.schema = 99' .vbw/record.json > "$TEST_ROOT/newer.json" && cp "$TEST_ROOT/newer.json" .vbw/record.json
  mkdir -p "${SEEN%/*}" && printf '2.0.40\n' > "$SEEN"
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(notice "$output")" == *"/vbw:update"* && "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.40" ]
}

@test "T136: the clone's worktrees share one record, so each update is offered once per clone" {
  plugin_version 2.0.41
  git worktree add -q "$TEST_ROOT/wt" -b other
  mkdir -p "$TEST_ROOT/wt/.vbw" && cp .vbw/record.json "$TEST_ROOT/wt/.vbw/record.json"
  mkdir -p "${SEEN%/*}" && printf '2.0.40\n' > "$SEEN"
  run session_start "$TEST_ROOT/wt"
  [[ "$(notice "$output")" == *"updated from 2.0.40 to 2.0.41"* ]] || { echo "$output"; false; }
  run session_start
  [[ "$(notice "$output")" != *"whats-new"* ]] || { echo "$output"; false; }
  [ "$(cat "$SEEN")" = "2.0.41" ]
}

@test "T136: the offer leaves no temporary file behind, and changes nothing in the work tree" {
  plugin_version 2.0.41
  session_start > /dev/null
  local before files
  before=$(find . \( -path ./.git -o -path ./.vbw/runtime \) -prune -o -type f -print | LC_ALL=C sort | xargs shasum)
  files=$(find "${SEEN%/*}" -type f | LC_ALL=C sort)
  printf '2.0.40\n' > "$SEEN"
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(notice "$output")" == *"whats-new"* ]]
  [ "$(cat "$SEEN")" = "2.0.41" ]
  [ "$(find . \( -path ./.git -o -path ./.vbw/runtime \) -prune -o -type f -print | LC_ALL=C sort | xargs shasum)" = "$before" ]
  [ "$(find "${SEEN%/*}" -type f | LC_ALL=C sort)" = "$files" ]
}

@test "T136: the status line, the hooks and doctor reach no network (the update check is Claude Code's auto-update, never VBW's)" {
  local f
  for f in hooks/session-start.sh hooks/stop.sh lib/cmd-doctor.sh scripts/vbw-statusline.sh lib/cmd-statusline.sh; do
    if grep -vE '^[[:space:]]*#' "$PLUGIN_ROOT/$f" | grep -qE '(^|[^[:alnum:]_])(curl|wget|netcat|ssh|telnet)([^[:alnum:]_]|$)|ls-remote|git[[:space:]]+(fetch|pull|clone)'; then
      echo "$f reaches for the network"
      false
    fi
  done
}
