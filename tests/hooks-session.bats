#!/usr/bin/env bats
# SessionStart: one line of state in VBW projects, silence elsewhere, no writes,
# no resume directives (ledger D289).

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

session_start() {
  jq -nc --arg d "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $d}' | HOOK_PROJECT_DIR="$1" vbw_hook SessionStart
}

@test "outside a VBW project the hook says nothing" {
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "in a VBW project it gives the state and the next step, and writes no project file" {
  "$VBW" init > /dev/null
  local before
  before=$(find . \( -path ./.git -o -path ./.vbw/runtime \) -prune -o -type f -print | LC_ALL=C sort | xargs shasum)
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"project with space · M1 First milestone"* ]]
  [[ "$ctx" == *"Next: spec (needs you): Write the requirements for M1"* ]]
  [[ "$ctx" != *"resume"* ]]
  [ "$(find . \( -path ./.git -o -path ./.vbw/runtime \) -prune -o -type f -print | LC_ALL=C sort | xargs shasum)" = "$before" ]
}

@test "a corrupt record is reported, not hidden" {
  "$VBW" init > /dev/null
  printf '{"schema": "damaged"}' > .vbw/record.json
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"record is corrupt"* ]]
}

@test "a project made by a newer VBW asks for an update, not /vbw:vibe" {
  "$VBW" init > /dev/null
  jq '.schema = 99' .vbw/record.json > "$TEST_ROOT/newer.json"
  cp "$TEST_ROOT/newer.json" .vbw/record.json
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"needs a newer VBW"* && "$ctx" == *"/vbw:update"* ]]
  [[ "$ctx" != *"Continue with /vbw:vibe"* ]]
  [[ "$(printf '%s' "$output" | jq -r '.systemMessage')" == *"/vbw:update"* ]]
}

@test "a session started in a subfolder of a VBW project gets the project's state and is told the project folder" {
  "$VBW" init > /dev/null
  mkdir -p "src/Sub Folder With Spaces"
  run session_start "$PROJECT/src/Sub Folder With Spaces"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"VBW project (project with space · M1 First milestone"* ]] || { echo "$ctx"; false; }
  [[ "$ctx" == *"This session started in src/Sub Folder With Spaces, a subfolder of the project at $PROJECT: VBW's paths (.vbw/, plan files) are relative to $PROJECT."* ]] || { echo "$ctx"; false; }
  [[ "$ctx" != *"guards are off"* ]]
  # A record above the git top is another project's, as for the kernel: nothing is said.
  mkdir -p "inner repo" && git -C "inner repo" init -q
  run session_start "$PROJECT/inner repo"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "VBW 1's command copies are removed (they would shadow VBW 2's commands); nothing else is touched" {
  local dir="$CLAUDE_CONFIG_DIR/commands/vbw"
  mkdir -p "$dir" "$CLAUDE_CONFIG_DIR/commands/mine"
  printf -- '---\nname: vbw:init\ndescription: x\n---\nbody\n' > "$dir/init.md"
  printf -- '---\nname: vbw:vibe\n---\nbody\n' > "$dir/vibe.md"
  printf -- '---\nname: my-own\n---\nname: vbw:not-frontmatter\n' > "$dir/mine.md"
  printf 'name: vbw:no-frontmatter\n' > "$dir/plain.md"
  printf -- '---\nname: vbw:elsewhere\n---\n' > "$CLAUDE_CONFIG_DIR/commands/mine/keep.md"
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"removed 2 outdated VBW 1 command copies"* ]]
  # The user sees it before typing anything (the session already loaded the copies).
  [[ "$(printf '%s' "$output" | jq -r .systemMessage)" == *"Type /reload-skills"* ]]
  [ ! -e "$dir/init.md" ] && [ ! -e "$dir/vibe.md" ]
  [ -f "$dir/mine.md" ] && [ -f "$dir/plain.md" ]
  [ -f "$CLAUDE_CONFIG_DIR/commands/mine/keep.md" ]
}

@test "the copies' directory is removed once empty, and a clean setup says nothing" {
  local dir="$CLAUDE_CONFIG_DIR/commands/vbw"
  mkdir -p "$dir"
  printf -- '---\nname: vbw:init\n---\n' > "$dir/init.md"
  run session_start "$PROJECT"
  [ ! -d "$dir" ]
  run session_start "$PROJECT"
  [ -z "$output" ]
}

@test "only the config directory this session uses is cleaned" {
  mkdir -p "$HOME/.claude/commands/vbw" "$TEST_ROOT/other/commands/vbw"
  printf -- '---\nname: vbw:init\n---\n' > "$HOME/.claude/commands/vbw/init.md"
  printf -- '---\nname: vbw:init\n---\n' > "$TEST_ROOT/other/commands/vbw/init.md"
  CLAUDE_CONFIG_DIR="$TEST_ROOT/other" run session_start "$PROJECT"
  [ ! -e "$TEST_ROOT/other/commands/vbw/init.md" ]
  [ -f "$HOME/.claude/commands/vbw/init.md" ]
}

@test "a VBW 1 project is told its plan is safe and how to bring it in, and nothing is written" {
  mkdir .vbw-planning && printf '# Project\n' > .vbw-planning/PROJECT.md
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'VBW 2 leaves it untouched, and /vbw:vibe or /vbw:convert'
  [ ! -e .vbw ]
  [ "$(cat .vbw-planning/PROJECT.md)" = "# Project" ]
}
