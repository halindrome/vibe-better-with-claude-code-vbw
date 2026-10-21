#!/usr/bin/env bats
# R159 (docs/rigor.md): a re-plan never raises the tier of a phase that has
# started (a plan no longer planned, or an escalation) or finished (every plan
# done, or its milestone shipped); the minimum rigor is judged for phases that
# have not started only. When the signals of a started or finished phase now
# call for a higher tier, the re-plan is not refused for it and the phase keeps
# its tier, reasons and predicted tier. A tier forced with vbw config rigor
# reaches only the phases that have not started. In automatic mode a phase that
# has not started and is planned below its floor is still refused, naming the
# phase, the minimum and the signals. An escalation is never lowered. L1.

load helper
load replan-helper
load fixture-helper

built_project() {
  vbw_setup
  replan_project
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# tiers PHASE: the phase's tier, reasons and predicted tier.
tiers() { replan_part ".phases[] | select(.id == \"$1\") | {tier, reasons, predicted}"; }

# grow: P1's planned file is now large enough for its signals to call for deep.
grow() { head -c 600000 /dev/zero | tr '\0' 'x' > src/a.txt; }

@test "R159: a started phase whose signals now call for a higher tier is not refused and keeps its tier, reasons and predicted tier" {
  replan_start P1.1
  local before
  before=$(tiers P1)
  grow
  replan_accepted full "$REPLAN_DOC"
  [ "$(tiers P1)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(tiers P1)"; false; }
}

@test "R159: the same holds when the re-plan gives the started phase no tier of its own" {
  replan_start P1.1
  local before
  before=$(tiers P1)
  grow
  replan_accepted full "$(replan_doc '(.phases[] | select(.id == "P1")) |= del(.tier)')"
  [ "$(tiers P1)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(tiers P1)"; false; }
}

@test "R159: a finished phase (every plan done) whose signals now call for a higher tier keeps its tier, reasons and predicted tier" {
  replan_start P1.1
  replan_start P1.2
  local before
  before=$(tiers P1)
  grow
  replan_accepted full "$REPLAN_DOC"
  [ "$(tiers P1)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(tiers P1)"; false; }
}

@test "R159: with the tier forced to deep, a re-plan leaves a started phase's tier unchanged and gives deep to the phase that has not started" {
  replan_start P1.1
  local before
  before=$(tiers P1)
  "$VBW" config rigor deep > /dev/null
  replan_accepted full "$REPLAN_DOC"
  [ "$(tiers P1)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(tiers P1)"; false; }
  [ "$(replan_part '.phases[] | select(.id == "P2") | .tier')" = '"deep"' ]
}

@test "R159: with the tier forced to express, a re-plan leaves a started phase's tier unchanged and gives express to the phase that has not started" {
  replan_start P1.1
  local before
  before=$(tiers P1)
  "$VBW" config rigor express > /dev/null
  replan_accepted full "$(replan_doc '.phases[] |= del(.tier)')"
  [ "$(tiers P1)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(tiers P1)"; false; }
  [ "$(replan_part '.phases[] | select(.id == "P2") | .tier')" = '"express"' ]
}

@test "R159: with the tier forced to standard, a finished phase keeps its tier and reasons" {
  replan_start P1.1
  replan_start P1.2
  "$VBW" tier raise P1 deep "a test raised it" > /dev/null
  local before
  before=$(tiers P1)
  "$VBW" config rigor standard > /dev/null
  replan_accepted full "$REPLAN_DOC"
  [ "$(tiers P1)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(tiers P1)"; false; }
}

@test "R159: in automatic mode a phase that has not started, planned below its floor, is still refused, naming the phase, the minimum and the signals" {
  replan_start P1.1
  replan_refused full "$(replan_doc '(.plans[] | select(.id == "P2.1")).files = ["src/payments/charge.js"]')"
  [[ "$output" == *"P2"* ]] || { echo "$output"; false; }
  [[ "$output" == *"deep"* ]] || { echo "$output"; false; }
  [[ "$output" == *"risk"* ]] || { echo "$output"; false; }
}

@test "R159: an escalation is never lowered by a re-plan, in automatic or forced mode" {
  replan_start P1.1
  "$VBW" tier raise P1 deep "a test raised it" > /dev/null
  replan_accepted full "$REPLAN_DOC"
  [ "$(replan_part '.phases[] | select(.id == "P1") | .tier')" = '"deep"' ]
  "$VBW" config rigor express > /dev/null
  replan_accepted full "$(replan_doc '.phases[] |= del(.tier)')"
  [ "$(replan_part '.phases[] | select(.id == "P1") | .tier')" = '"deep"' ]
}
