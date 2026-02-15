#!/usr/bin/env bats

load test_helper

# --- Task 1: Heredoc commit validation ---

@test "heredoc commit validation extracts correct message" {
  INPUT='{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat(core): add heredoc feature\n\nCo-Authored-By: Test\nEOF\n)\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  # Should NOT contain "does not match format" since feat(core): is valid
  [[ "$output" != *"does not match format"* ]]
}

@test "heredoc commit does not get overwritten by -m extraction" {
  # Heredoc with valid format followed by -m with invalid format
  # If heredoc is correctly prioritized, it should use the heredoc message
  INPUT='{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat(test): valid heredoc\nEOF\n)\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"does not match format"* ]]
}

@test "invalid heredoc commit is flagged" {
  # Build input with actual newlines in the heredoc body
  local input
  input=$(printf '{"tool_input":{"command":"git commit -m \\"$(cat <<EOF)\\"\\nbad commit no type\\nEOF"}}')
  run bash -c "printf '%s' '$input' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "does not match format"
}

# --- Task 4: Stack detection expansion ---

@test "detect-stack finds Rust via Cargo.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/Cargo.toml"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("rust")' >/dev/null
}

@test "detect-stack finds Go via go.mod" {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "module example.com/test" > "$tmpdir/go.mod"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("go")' >/dev/null
}

@test "detect-stack finds Python via pyproject.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/pyproject.toml"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("python")' >/dev/null
}

# --- Task 5: Security filter hardening ---

@test "security-filter allows .vbw-planning/ write when VBW marker present" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter blocks .env file access" {
  INPUT='{"tool_input":{"file_path":".env"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "sensitive file"
}

# --- Task 3: Session config cache ---

@test "session config cache file is written at session start" {
  setup_temp_dir
  create_test_config
  CACHE_FILE="/tmp/vbw-config-cache-$(id -u)"
  rm -f "$CACHE_FILE" 2>/dev/null
  run bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/session-start.sh'"
  [ -f "$CACHE_FILE" ]
  grep -q "VBW_EFFORT=" "$CACHE_FILE"
  grep -q "VBW_AUTONOMY=" "$CACHE_FILE"
  teardown_temp_dir
}

# --- Task 2: zsh glob guard ---

@test "file-guard exits 0 when no plan files exist" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/src/index.ts"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

# --- Isolation marker lifecycle (fix/isolation-marker-lifecycle) ---

@test "security-filter allows write with only .vbw-session (no .active-agent)" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # No .active-agent
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/milestones/default/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter resolves markers from FILE_PATH project root" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.vbw-planning" "$REPO_B/.vbw-planning"
  touch "$REPO_A/.vbw-planning/.gsd-isolation"
  # Repo A has no markers — would block if CWD-based
  # Repo B has .gsd-isolation AND .vbw-session — should allow
  touch "$REPO_B/.vbw-planning/.gsd-isolation"
  echo "session" > "$REPO_B/.vbw-planning/.vbw-session"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter blocks when target repo has isolation but no markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  # No .active-agent, no .vbw-session
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 2 ]
}

@test "agent-start handles vbw: prefixed agent_type" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"vbw:vbw-scout"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  teardown_temp_dir
}

@test "agent-start creates count file for reference counting" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  # Start two agents
  echo '{"agent_type":"vbw-scout"}' | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo '{"agent_type":"vbw-lead"}' | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "2" ]
  teardown_temp_dir
}

@test "agent-stop decrements count and preserves marker when agents remain" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "lead" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  # Marker should still exist (one agent remaining)
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "agent-stop removes marker when last agent stops" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  # Both marker and count should be gone
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "prompt-preflight creates .vbw-session for expanded command content" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  # Simulate expanded slash command with YAML frontmatter containing name: vbw:vibe
  INPUT='{"prompt":"---\nname: vbw:vibe\ndescription: Main entry point\n---\n# VBW Vibe\nPlan mode..."}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight does NOT delete .vbw-session on plain text follow-up" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # Plain text follow-up (e.g., user answering a question)
  INPUT='{"prompt":"yes, go ahead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  # Marker should still exist
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight removes .vbw-session on non-VBW slash command" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # Non-VBW slash command
  INPUT='{"prompt":"/gsd:status"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  # Marker should be removed
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}
