#!/usr/bin/env bats
# Tests for statusline_hide_limits and statusline_hide_limits_for_api_key config switches.
# Verifies L3 (usage/limits line) suppression behavior.

load test_helper

STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
}

teardown() {
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
  teardown_temp_dir
}

# --- Default: L3 is present ---

@test "default config: L3 (3rd line) is present and non-empty" {
  local repo="$TEST_TEMP_DIR/repo-default"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": false
}
JSON

  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  [ -n "$l3" ]
}

# --- statusline_hide_limits: true suppresses L3 ---

@test "statusline_hide_limits true: L3 is blank" {
  local repo="$TEST_TEMP_DIR/repo-hide-all"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": true,
  "statusline_hide_limits_for_api_key": false
}
JSON

  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  [ -z "$l3" ]
}

# --- statusline_hide_limits_for_api_key: true with no OAuth (API key path) ---

@test "statusline_hide_limits_for_api_key true without OAuth: L3 is blank" {
  local repo="$TEST_TEMP_DIR/repo-hide-api"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": true
}
JSON

  cd "$repo"
  # Ensure no OAuth token is available — FETCH_OK will be "noauth" (the else branch)
  unset VBW_OAUTH_TOKEN
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  [ -z "$l3" ]
}

# --- statusline_hide_limits_for_api_key: true with OAuth token (not suppressed) ---

@test "statusline_hide_limits_for_api_key true with OAuth token: L3 still has content" {
  local repo="$TEST_TEMP_DIR/repo-hide-api-oauth"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": true
}
JSON

  cd "$repo"
  # With a fake OAuth token, the API call will fail → FETCH_OK="fail"
  # "fail" is excluded from suppression, so L3 should still be present
  export VBW_OAUTH_TOKEN="fake_token_for_test"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  unset VBW_OAUTH_TOKEN
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  [ -n "$l3" ]
}
