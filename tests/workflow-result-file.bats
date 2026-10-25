#!/usr/bin/env bats
# A workflow's result reaches the session either inline or, when Claude Code saves
# it to a file, wrapped as {summary, agentCount, logs, result}: the returned object
# sits under `result` (found 2026-10-24: a session read `map` at the file's top level
# and failed). The skills that read a result field say where it sits and read it
# with jq. L1.

ROOT="$BATS_TEST_DIRNAME/.."

@test "the router says a saved workflow result holds the returned object under result" {
  grep -q 'saves it to a file, the object sits under `result`' "$ROOT/plugin/skills/vibe/SKILL.md"
}

@test "the map and what's-next skills read the field they need under result in a saved file" {
  grep -q "jq -er '.result.map'" "$ROOT/plugin/skills/map/SKILL.md"
  grep -q "jq -er '.result.map'" "$ROOT/plugin/skills/vibe/SKILL.md"
  grep -q "jq -c '.result.recommendation'" "$ROOT/plugin/skills/whats-next/SKILL.md"
}

@test "docs/workflows.md names where a saved result holds the returned object" {
  grep -q 'result saved to a file, the returned object sits under `result`' "$ROOT/docs/workflows.md"
}
