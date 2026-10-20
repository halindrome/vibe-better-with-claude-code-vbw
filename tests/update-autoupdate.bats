#!/usr/bin/env bats
# T136 (docs/update.md): VBW makes no network call to find out whether a new
# version is out. Claude Code does that: its auto-update refreshes the marketplace
# and updates the plugin in the background, and says "Plugin updated: vbw · Run
# /reload-plugins to apply". For a third-party marketplace like vbw-marketplace it is
# off until the user turns it on, so vbw doctor reports whether it is on, with the way
# to turn it on. The state is read from the files Claude Code keeps: the autoUpdate of
# the marketplace in settings (extraKnownMarketplaces), else in known_marketplaces.json
# under the plugins folder, else off; DISABLE_UPDATES, DISABLE_AUTOUPDATER and
# CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC switch the whole pass off unless
# FORCE_AUTOUPDATE_PLUGINS is set. L1: fixture files in the test's Claude config folder.

load helper

setup() {
  vbw_setup
  vbw_git_project
  unset DISABLE_UPDATES DISABLE_AUTOUPDATER CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC FORCE_AUTOUPDATE_PLUGINS CLAUDE_CODE_PLUGIN_CACHE_DIR
  PLUGINS="$CLAUDE_CONFIG_DIR/plugins"
  mkdir -p "$PLUGINS"
}

teardown() { vbw_teardown; }

# known JSON: the marketplaces Claude Code has fetched.
known() { printf '%s\n' "$1" > "$PLUGINS/known_marketplaces.json"; }
KNOWN_OFF='{"claude-plugins-official": {"source": {"source": "github", "repo": "anthropics/claude-plugins-official"}}, "vbw-marketplace": {"source": {"source": "github", "repo": "swt-labs/vibe-better-with-claude-code-vbw"}, "lastUpdated": "2026-10-20T22:40:54.509Z"}}'
KNOWN_ON='{"vbw-marketplace": {"source": {"source": "github", "repo": "swt-labs/vibe-better-with-claude-code-vbw"}, "autoUpdate": true}}'
KNOWN_FALSE='{"vbw-marketplace": {"source": {"source": "github", "repo": "swt-labs/vibe-better-with-claude-code-vbw"}, "autoUpdate": false}}'

# settings FILE AUTOUPDATE: a settings file that declares vbw-marketplace with autoUpdate.
settings() {
  mkdir -p "$(dirname "$1")"
  jq -n --argjson a "$2" '{extraKnownMarketplaces: {"vbw-marketplace": {source: {source: "github", repo: "swt-labs/vibe-better-with-claude-code-vbw"}, autoUpdate: $a}}}' > "$1"
}

# update_lines: doctor's lines about auto-update, each with its fix.
update_lines() {
  printf '%s\n' "$output" | awk '/auto-update/ { print; keep = 1; next } /^    fix: / && keep { print; next } { keep = 0 }'
}

@test "T136: doctor says nothing about auto-update when VBW's marketplace is not one Claude Code knows here" {
  run "$VBW" doctor < /dev/null
  [ -z "$(update_lines)" ] || { update_lines; false; }
  known '{"claude-plugins-official": {"source": {"source": "github", "repo": "anthropics/claude-plugins-official"}, "autoUpdate": true}}'
  run "$VBW" doctor < /dev/null
  [ -z "$(update_lines)" ] || { update_lines; false; }
}

@test "T136: a third-party marketplace is off by default: doctor warns that nothing will tell the user and gives the way to turn it on" {
  known "$KNOWN_OFF"
  run "$VBW" doctor < /dev/null
  local lines
  lines=$(update_lines)
  [[ "$lines" == '! auto-update is off for VBW'*'(vbw-marketplace)'* ]] || { echo "$output"; false; }
  [[ "$lines" == *"does not fetch a new VBW"*"nothing tells you one is out"* ]] || { echo "$lines"; false; }
  [[ "$lines" == *"fix: "*"/vbw:update"*"/plugin"*"Marketplaces"*"vbw-marketplace"*"Enable auto-update"* ]] || { echo "$lines"; false; }
}

@test "T136: the warning does not fail doctor" {
  known "$KNOWN_OFF"
  run "$VBW" doctor < /dev/null
  [[ "$output" == *"! auto-update is off"* ]]
  ! printf '%s\n' "$output" | grep -E '^✗' | grep -q 'auto-update'
}

@test "T136: auto-update on in known_marketplaces.json: doctor says VBW updates itself and how the user is told" {
  known "$KNOWN_ON"
  run "$VBW" doctor < /dev/null
  local lines
  lines=$(update_lines)
  [[ "$lines" == '✓ auto-update is on for VBW'*'(vbw-marketplace)'* ]] || { echo "$output"; false; }
  [[ "$lines" == *"Plugin updated"*"/reload-plugins"* ]] || { echo "$lines"; false; }
  [[ "$lines" != *"fix:"* ]]
}

@test "T136: an explicit false in known_marketplaces.json is off" {
  known "$KNOWN_FALSE"
  run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '! auto-update is off'* ]] || { echo "$output"; false; }
}

@test "T136: the user settings' autoUpdate wins over known_marketplaces.json, both ways" {
  known "$KNOWN_FALSE"
  settings "$CLAUDE_CONFIG_DIR/settings.json" true
  run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '✓ auto-update is on'* ]] || { echo "$output"; false; }
  known "$KNOWN_ON"
  settings "$CLAUDE_CONFIG_DIR/settings.json" false
  run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '! auto-update is off'* ]] || { echo "$output"; false; }
}

@test "T136: settings declaring the marketplace count even when known_marketplaces.json does not list it" {
  known '{}'
  settings "$CLAUDE_CONFIG_DIR/settings.json" true
  run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '✓ auto-update is on'* ]] || { echo "$output"; false; }
}

@test "T136: a project's local settings override its shared settings, which override the user's (Claude Code's precedence)" {
  known "$KNOWN_OFF"
  settings "$CLAUDE_CONFIG_DIR/settings.json" false
  settings .claude/settings.json true
  run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '✓ auto-update is on'* ]] || { echo "$output"; false; }
  settings .claude/settings.local.json false
  run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '! auto-update is off'* ]] || { echo "$output"; false; }
}

@test "T136: a settings entry without autoUpdate leaves the choice to known_marketplaces.json" {
  known "$KNOWN_ON"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf '%s\n' '{"extraKnownMarketplaces": {"vbw-marketplace": {"source": {"source": "github", "repo": "x/y"}}}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '✓ auto-update is on'* ]] || { echo "$output"; false; }
}

@test "T136: an environment that switches Claude Code's updates off makes auto-update off, whatever the setting, and the fix names the variable" {
  known "$KNOWN_ON"
  local v
  for v in DISABLE_UPDATES DISABLE_AUTOUPDATER CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do
    env "$v=1" "$VBW" doctor < /dev/null > "$TEST_ROOT/out" 2>&1 || true
    output=$(cat "$TEST_ROOT/out")
    local lines
    lines=$(update_lines)
    [[ "$lines" == '! auto-update is off'*"$v"* ]] || { echo "$v: $output"; false; }
    [[ "$lines" == *"fix: "*"unset $v"*"FORCE_AUTOUPDATE_PLUGINS"* ]] || { echo "$v: $lines"; false; }
  done
}

@test "T136: FORCE_AUTOUPDATE_PLUGINS keeps auto-update on under those variables" {
  known "$KNOWN_ON"
  DISABLE_AUTOUPDATER=1 FORCE_AUTOUPDATE_PLUGINS=1 run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '✓ auto-update is on'* ]] || { echo "$output"; false; }
}

@test "T136: CLAUDE_CODE_PLUGIN_CACHE_DIR moves the plugins folder Claude Code keeps known_marketplaces.json in" {
  mkdir -p "$TEST_ROOT/elsewhere"
  printf '%s\n' "$KNOWN_ON" > "$TEST_ROOT/elsewhere/known_marketplaces.json"
  known "$KNOWN_OFF"
  CLAUDE_CODE_PLUGIN_CACHE_DIR="$TEST_ROOT/elsewhere" run "$VBW" doctor < /dev/null
  [[ "$(update_lines)" == '✓ auto-update is on'* ]] || { echo "$output"; false; }
}

@test "T136: a known_marketplaces.json or settings file that cannot be read is skipped, not an error" {
  printf 'not json' > "$PLUGINS/known_marketplaces.json"
  printf '{broken' > "$CLAUDE_CONFIG_DIR/settings.json"
  run "$VBW" doctor < /dev/null
  [[ "$output" == *"git "* ]]
  [ -z "$(update_lines)" ] || { update_lines; false; }
}

@test "T136: doctor reads the files and changes nothing" {
  known "$KNOWN_OFF"
  settings "$CLAUDE_CONFIG_DIR/settings.json" false
  local before
  before=$(find "$CLAUDE_CONFIG_DIR" -type f | LC_ALL=C sort | xargs shasum)
  run "$VBW" doctor < /dev/null
  [ "$(find "$CLAUDE_CONFIG_DIR" -type f | LC_ALL=C sort | xargs shasum)" = "$before" ]
}

@test "T136: /vbw:doctor tells the user to make the auto-update change in Claude Code, and /vbw:update names auto-update" {
  grep -q 'auto-update' "$PLUGIN_ROOT/skills/doctor/SKILL.md"
  grep -q '/plugin' "$PLUGIN_ROOT/skills/doctor/SKILL.md"
  local u="$PLUGIN_ROOT/skills/update/SKILL.md"
  grep -q 'auto-update' "$u"
  grep -q 'Enable auto-update' "$u"
  grep -q 'off by default' "$u"
}

@test "T136: docs/update.md says what Claude Code does and what VBW does" {
  local d="$REPO_ROOT/docs/update.md"
  [ -f "$d" ]
  grep -q 'VBW makes no network call' "$d"
  grep -q '/vbw:update' "$d"
  grep -q 'claude plugin marketplace update vbw-marketplace' "$d"
  grep -q 'it is off$' "$d"
  grep -q '^until you turn it on' "$d"
  grep -q 'Marketplaces' "$d"
  grep -q 'Enable' "$d"
  grep -q 'Plugin updated: vbw · Run /reload-plugins to apply' "$d"
  grep -q 'autoUpdate' "$d"
  grep -q 'FORCE_AUTOUPDATE_PLUGINS' "$d"
  grep -q 'DISABLE_AUTOUPDATER' "$d"
  grep -q '/vbw:whats-new' "$d"
  grep -q 'seen-version' "$d"
  grep -q '/vbw:doctor' "$d"
  grep -q 'code.claude.com/docs/en/plugins/install#keep-plugins-updated' "$d"
  grep -q 'code.claude.com/docs/en/plugins/loading#when-auto-update-runs' "$d"
}

@test "T136: docs/diagnostics.md says vbw doctor reports auto-update and points to docs/update.md" {
  sed -n '/vbw doctor/,$p' "$REPO_ROOT/docs/diagnostics.md" | grep -q 'auto-update'
  grep -q 'docs/update.md' "$REPO_ROOT/docs/diagnostics.md"
}
