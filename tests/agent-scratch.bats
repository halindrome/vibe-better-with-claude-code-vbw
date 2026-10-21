#!/usr/bin/env bats
# R177 (docs/guards.md, D300): agents have one scratch folder inside the
# project, .vbw/runtime/scratch/, and every text that tells them where to write
# names that same folder: the guard's refusal, the Dev and Lead briefs and the
# guards documentation; the briefs never send an agent to /tmp. The Lead brief
# keeps its dependency rule on `after` (QA finding F136). L1.

load helper

SCRATCH='.vbw/runtime/scratch/'

@test "R177: the refusal's advice, the Dev brief, the Lead brief and docs/guards.md name the one scratch folder" {
  grep -qF "put scratch work in $SCRATCH" "$PLUGIN_ROOT/hooks/common.jq"
  grep -qF "$SCRATCH" "$PLUGIN_ROOT/agents/dev.md"
  grep -qF "$SCRATCH" "$PLUGIN_ROOT/agents/lead.md"
  grep -qF "$SCRATCH" "$PLUGIN_ROOT/../docs/guards.md"
}

@test "R177: no brief and no refusal sends an agent to /tmp or to .vbw/runtime/ itself" {
  ! grep -En 'go in `\.vbw/runtime/`|scratch work in \.vbw/runtime/"' "$PLUGIN_ROOT/agents/dev.md" "$PLUGIN_ROOT/agents/lead.md" "$PLUGIN_ROOT/hooks/common.jq" || false
  grep -qF 'never `/tmp`' "$PLUGIN_ROOT/agents/dev.md"
  grep -qF 'never `/tmp`' "$PLUGIN_ROOT/agents/lead.md"
}

@test "R177 (F136): the Lead brief keeps its dependency rule on after" {
  grep -qF '`after`' "$PLUGIN_ROOT/agents/lead.md"
}
