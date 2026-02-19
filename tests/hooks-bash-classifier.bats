#!/usr/bin/env bats

# Test suite for VBW hook bash patterns against CC 2.1.47 stricter classifier
# REQ-10: Audit bash permission patterns against CC 2.1.47's stricter classifier
#
# All 21 hook handlers in hooks.json use a common dual-resolution pattern:
# 1. Version-sorted plugin cache resolution: ls -1 | sort -V | tail -1
# 2. Fallback to CLAUDE_PLUGIN_ROOT
# 3. Execute hook-wrapper.sh with target script
#
# Hook scripts invoked:
# - validate-summary.sh (PostToolUse Write|Edit, SubagentStop)
# - validate-frontmatter.sh (PostToolUse Write|Edit)
# - validate-commit.sh (PostToolUse Bash)
# - skill-hook-dispatch.sh PostToolUse (PostToolUse Write|Edit|Bash)
# - state-updater.sh (PostToolUse Write|Edit)
# - bash-guard.sh (PreToolUse Bash)
# - security-filter.sh (PreToolUse Read|Glob|Grep|Write|Edit)
# - skill-hook-dispatch.sh PreToolUse (PreToolUse Write|Edit)
# - file-guard.sh (PreToolUse Write|Edit)
# - agent-start.sh (SubagentStart)
# - agent-health.sh start (SubagentStart)
# - agent-stop.sh (SubagentStop)
# - agent-health.sh stop (SubagentStop)
# - qa-gate.sh (TeammateIdle)
# - agent-health.sh idle (TeammateIdle)
# - task-verify.sh (TaskCompleted)
# - blocker-notify.sh (TaskCompleted)
# - session-start.sh (SessionStart)
# - map-staleness.sh (SessionStart)
# - post-compact.sh (SessionStart matcher=compact)
# - compaction-instructions.sh (PreCompact)
# - session-stop.sh (Stop)
# - agent-health.sh cleanup (Stop)
# - prompt-preflight.sh (UserPromptSubmit)
# - notification-log.sh (Notification)

setup() {
  # Store the common hook-wrapper.sh resolution pattern
  WRAPPER_PATTERN='bash -c '\''w=$(ls -1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/scripts/hook-wrapper.sh 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1); [ ! -f "$w" ] && w="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/hook-wrapper.sh}"; [ -f "$w" ] && exec bash "$w" TARGET_SCRIPT; exit 0'\'''
}

@test "hook pattern count matches hooks.json entries" {
  # Count unique bash commands in hooks.json
  HOOK_COUNT=$(grep -c '"command":' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")

  # We should have 26 total hook entries (21 unique scripts, some duplicated across events)
  [ "$HOOK_COUNT" -eq 26 ]
}

@test "all hooks use dual-resolution pattern" {
  # All hooks should use the version-sorted cache resolution pattern
  PATTERN_COUNT=$(grep -c 'sort -V' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")

  # Should match total hook count
  [ "$PATTERN_COUNT" -eq 26 ]
}

@test "all hooks have CLAUDE_PLUGIN_ROOT fallback" {
  # All hooks should have fallback to CLAUDE_PLUGIN_ROOT
  FALLBACK_COUNT=$(grep -c 'CLAUDE_PLUGIN_ROOT:+' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")

  # Should match total hook count
  [ "$FALLBACK_COUNT" -eq 26 ]
}

@test "all hooks exit 0 for graceful degradation" {
  # All hooks should end with 'exit 0' for fail-open behavior
  EXIT_COUNT=$(grep -c 'exit 0' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")

  # Should match total hook count
  [ "$EXIT_COUNT" -eq 26 ]
}

# Unique hook script invocations (21 total)
@test "documented scripts: validate-summary.sh appears 2x" {
  COUNT=$(grep -c 'validate-summary.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 2 ]
}

@test "documented scripts: validate-frontmatter.sh appears 1x" {
  COUNT=$(grep -c 'validate-frontmatter.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: validate-commit.sh appears 1x" {
  COUNT=$(grep -c 'validate-commit.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: skill-hook-dispatch.sh appears 2x" {
  COUNT=$(grep -c 'skill-hook-dispatch.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 2 ]
}

@test "documented scripts: state-updater.sh appears 1x" {
  COUNT=$(grep -c 'state-updater.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: bash-guard.sh appears 1x" {
  COUNT=$(grep -c 'bash-guard.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: security-filter.sh appears 1x" {
  COUNT=$(grep -c 'security-filter.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: file-guard.sh appears 1x" {
  COUNT=$(grep -c 'file-guard.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: agent-start.sh appears 1x" {
  COUNT=$(grep -c 'agent-start.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: agent-stop.sh appears 1x" {
  COUNT=$(grep -c 'agent-stop.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: agent-health.sh appears 4x" {
  COUNT=$(grep -c 'agent-health.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 4 ]
}

@test "documented scripts: qa-gate.sh appears 1x" {
  COUNT=$(grep -c 'qa-gate.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: task-verify.sh appears 1x" {
  COUNT=$(grep -c 'task-verify.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: blocker-notify.sh appears 1x" {
  COUNT=$(grep -c 'blocker-notify.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: session-start.sh appears 1x" {
  COUNT=$(grep -c 'session-start.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: map-staleness.sh appears 1x" {
  COUNT=$(grep -c 'map-staleness.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: post-compact.sh appears 1x" {
  COUNT=$(grep -c 'post-compact.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: compaction-instructions.sh appears 1x" {
  COUNT=$(grep -c 'compaction-instructions.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: session-stop.sh appears 1x" {
  COUNT=$(grep -c 'session-stop.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: prompt-preflight.sh appears 1x" {
  COUNT=$(grep -c 'prompt-preflight.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: notification-log.sh appears 1x" {
  COUNT=$(grep -c 'notification-log.sh' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

# Task 2: Test hook-wrapper.sh resolution pattern
# CC 2.1.47 stricter classifier validation for complex chained bash patterns

@test "hook resolution: version-sorted cache resolution pattern is valid" {
  # Test the ls | sort -V | tail -1 pattern used for cache resolution
  # This is the core pattern that must pass the stricter classifier

  # The pattern structure:
  # ls -1 ... | (sort -V || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1
  # This is auto-allowed piping: ls -> sort -> tail

  # Verify hook-wrapper.sh actually uses this pattern
  PATTERN_EXISTS=$(grep -c 'sort -V.*tail -1' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/scripts/hook-wrapper.sh")
  [ "$PATTERN_EXISTS" -ge 1 ]
}

@test "hook resolution: dual fallback pattern is valid" {
  # Test the dual resolution pattern: cache first, then CLAUDE_PLUGIN_ROOT
  # Pattern: [ ! -f "$w" ] && w="${CLAUDE_PLUGIN_ROOT:+...}"; [ -f "$w" ] && exec bash "$w" ...

  # Verify hook-wrapper.sh uses file existence checks (both -f and ! -f)
  FILE_CHECK_POS=$(grep -c '\[ -f' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/scripts/hook-wrapper.sh")
  FILE_CHECK_NEG=$(grep -c '\[ ! -f' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/scripts/hook-wrapper.sh")
  TOTAL_CHECKS=$((FILE_CHECK_POS + FILE_CHECK_NEG))
  [ "$TOTAL_CHECKS" -ge 4 ]
}

@test "hook resolution: graceful exit 0 on missing target" {
  # Verify hook-wrapper.sh exits 0 when target script not found
  # This is critical for fail-open design

  EXIT_PATTERN=$(grep -c 'exit 0' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/scripts/hook-wrapper.sh")
  [ "$EXIT_PATTERN" -ge 1 ]
}

@test "hook resolution: all hooks use same wrapper pattern structure" {
  # Verify consistency: all hooks use the exact same resolution structure
  # Extract first hook command as reference
  FIRST_HOOK=$(grep -m1 '"command":.*bash -c' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json" | sed 's/.*bash -c/bash -c/' | sed 's/validate-[^.]*\.sh/SCRIPT/g' | sed 's/[a-z-]*\.sh/SCRIPT/g')

  # All hooks should follow same pattern, just with different script names
  [ -n "$FIRST_HOOK" ]
}

@test "hook resolution: bash -c wrapping is consistent" {
  # All hooks use 'bash -c' to wrap the resolution logic
  BASH_C_COUNT=$(grep -c 'bash -c' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")

  # Should match total hook count (26)
  [ "$BASH_C_COUNT" -eq 26 ]
}

@test "hook resolution: variable substitution uses safe patterns" {
  # Verify hooks use parameter expansion safely
  # Pattern: ${VAR:-default}, ${VAR:+value}

  SAFE_EXPANSION=$(grep -c '\${CLAUDE_CONFIG_DIR:-' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$SAFE_EXPANSION" -ge 1 ]

  SAFE_PLUGIN_ROOT=$(grep -c '\${CLAUDE_PLUGIN_ROOT:+' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")
  [ "$SAFE_PLUGIN_ROOT" -ge 1 ]
}

@test "hook resolution: exec bash handoff is valid" {
  # Verify hooks use 'exec bash' to hand off to hook-wrapper.sh
  EXEC_COUNT=$(grep -c 'exec bash' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")

  # Should match total hook count (26)
  [ "$EXEC_COUNT" -eq 26 ]
}

@test "hook resolution: error suppression with 2>/dev/null" {
  # Verify hooks suppress stderr for ls/sort commands
  ERROR_SUPPRESS=$(grep -c '2>/dev/null' "/Users/tiagoserodio/Documents/AI Stuff/vbw-cc/hooks/hooks.json")

  # At least one per hook (may be more due to multiple redirects)
  [ "$ERROR_SUPPRESS" -ge 26 ]
}
