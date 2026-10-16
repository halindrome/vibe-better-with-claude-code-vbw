#!/usr/bin/env bats
# R190, phase P148 (L1): when VBW starts planning, a build, a fix, QA or a
# background proof, its chat message says what starts and when it should end,
# in the words vbw next --json gives as .step.say ('Building P146.1 and
# P146.2: about 12 min, until around 14:20', or '...: no end time yet (VBW has
# timed fewer than 3 steps like this here)'). The router (/vbw:vibe) tells the
# session to say it as given; /vbw:status reports the running step and its end
# time in vbw status's words. These tests read the skills' text; what a real
# session says is the L3 scenario's (tests/l3-step-time.bats).

load helper

VIBE="$PLUGIN_ROOT/skills/vibe/SKILL.md"
STATUS="$PLUGIN_ROOT/skills/status/SKILL.md"

@test "R190: the router says step.say, as given, when it starts planning, a build, a fix, QA or a proof" {
  grep -qF 'step.say' "$VIBE" || { echo "the router never mentions step.say"; false; }
  local line
  line=$(grep -F 'step.say' "$VIBE" | head -1)
  for word in plan build fix qa prove; do
    printf '%s\n' "$line" | grep -qi "$word" || { echo "the step.say rule does not name $word: $line"; false; }
  done
  printf '%s\n' "$line" | grep -qiE 'as given|word for word|verbatim|unchanged' || { echo "the router may reword step.say: $line"; false; }
}

@test "R190: the router says it before the step starts, also for a background proof" {
  local line
  line=$(grep -F 'step.say' "$VIBE" | head -1)
  printf '%s\n' "$line" | grep -qiE 'before' || { echo "the step.say rule does not say when: $line"; false; }
  printf '%s\n' "$line" | grep -qiE 'background' || { echo "the step.say rule does not cover a background proof: $line"; false; }
}

@test "R190: /vbw:status reports the running step and its end time in vbw status's words" {
  grep -qiE 'running step' "$STATUS" || { echo "/vbw:status does not mention the running step"; false; }
  grep -qiE "end time" "$STATUS" || { echo "/vbw:status does not mention the end time"; false; }
  grep -qiE "(same|its own|vbw status'?s?) words|as vbw status (says|prints)" "$STATUS" || { echo "/vbw:status may reword the step"; false; }
}
