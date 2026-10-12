#!/usr/bin/env bats
# R177 (docs/guards.md, D300): agents have one scratch folder inside the
# project, .vbw/runtime/scratch/, and every text that tells them where to write
# names that same folder: the guard's refusal, the Dev and Lead briefs and the
# guards documentation. The Lead brief keeps its planning rules while saying so
# (QA finding F136: a rule sentence was cut to make room). L1.

load helper

SCRATCH='.vbw/runtime/scratch/'

@test "R177: the refusal's advice, the Dev brief, the Lead brief and docs/guards.md name the one scratch folder" {
  grep -qF "put scratch work in $SCRATCH" "$PLUGIN_ROOT/hooks/common.jq"
  grep -qF "scratch files go in \`$SCRATCH\`" "$PLUGIN_ROOT/agents/dev.md"
  grep -qF "Scratch files: \`$SCRATCH\`" "$PLUGIN_ROOT/agents/lead.md"
  grep -qF "Writing under \`$SCRATCH\` during a run" "$PLUGIN_ROOT/../docs/guards.md"
  grep -qF "put scratch work in $SCRATCH" "$PLUGIN_ROOT/../docs/guards.md"
}

@test "R177: no brief and no refusal sends an agent to /tmp or to .vbw/runtime/ itself" {
  ! grep -En 'go in `\.vbw/runtime/`|scratch work in \.vbw/runtime/"' "$PLUGIN_ROOT/agents/dev.md" "$PLUGIN_ROOT/agents/lead.md" "$PLUGIN_ROOT/hooks/common.jq"
  grep -qF 'never `/tmp`' "$PLUGIN_ROOT/agents/dev.md"
  grep -qF 'never `/tmp`' "$PLUGIN_ROOT/agents/lead.md"
}

@test "R177 (F136): the Lead brief keeps its first planning rule whole: real dependencies, no invented independence, no needless chains" {
  grep -qF '1. **Real dependencies.** `after` lists only plans whose output is truly needed. No invented independence, no needless chains.' "$PLUGIN_ROOT/agents/lead.md"
}
