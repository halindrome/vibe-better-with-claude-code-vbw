#!/usr/bin/env bats
# R191, phase P151 (L1): when VBW starts planning, a build, a fix, QA or a background
# proof, its chat message says the step's sentence (step.say) followed by the
# milestone's (road.say), exactly as vbw next --json gives them; /vbw:status passes
# the milestone's end on in vbw status's words. These tests read the skills' text;
# what a real session says is the L3 scenario's (tests/l3-road.bats).

load helper

VIBE="$PLUGIN_ROOT/skills/vibe/SKILL.md"
STATUS="$PLUGIN_ROOT/skills/status/SKILL.md"

@test "R191: the router says road.say with step.say, as given, before it starts a step" {
  grep -qF 'road.say' "$VIBE" || { echo "the router never mentions road.say"; false; }
  local line
  line=$(grep -F 'step.say' "$VIBE" | head -1)
  printf '%s\n' "$line" | grep -qF 'road.say' || { echo "road.say is not said with step.say: $line"; false; }
  printf '%s\n' "$line" | grep -qiE 'as given|word for word|verbatim|unchanged' || { echo "the router may reword the sentences: $line"; false; }
  for word in plan build fix qa prove background; do
    printf '%s\n' "$line" | grep -qi "$word" || { echo "the rule does not name $word: $line"; false; }
  done
}

@test "R191: /vbw:status passes the milestone's end on in vbw status's words" {
  grep -qiE "milestone'?s? end|milestone end" "$STATUS" || { echo "/vbw:status does not mention the milestone's end"; false; }
}
