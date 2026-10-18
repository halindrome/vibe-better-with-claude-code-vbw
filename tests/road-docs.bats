#!/usr/bin/env bats
# R191, phase P151 (L1): the docs explain the new estimate. docs/panel.md's 'Time
# left' section: time per unit at a tier (a plan's task, a fix round, a proof's
# unit, a QA phase, a requirement), the fallback ladder and its 3-step minimum,
# that side-by-side plans are not added (the longest counts), the proof's unit
# times (runs.json) and its learned ratio, the road's pieces, how the usual fix
# rounds are counted and named, what makes the road say 'no milestone end time
# yet', and that the history is this project's only (D433). docs/next.md
# describes road; docs/statusline.md says the status line shows the step's time
# only; docs/rigor.md says outcome.fix_rounds feeds the milestone's end; the README
# names the milestone's end where it describes the panel. Facts a reader needs, not
# exact sentences.

load helper

PANEL="$REPO_ROOT/docs/panel.md"
NEXT="$REPO_ROOT/docs/next.md"
STATUSLINE="$REPO_ROOT/docs/statusline.md"
RIGOR="$REPO_ROOT/docs/rigor.md"
README="$REPO_ROOT/README.md"

# section: docs/panel.md's 'Time left' section, its heading to the next one, as one lower-case line.
section() { sed -n '/^## Time left/,/^## /p' "$PANEL" | sed '$d' | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { printf '%s\n' "$1" | grep -qE -- "$2" || { echo "missing: $2"; return 1; }; }

@test "R191: docs/panel.md's Time left explains the time per unit at a tier and the fallback ladder with its 3-step minimum" {
  local s
  s=$(section)
  [ -n "$s" ] || { echo "docs/panel.md has no '## Time left' section"; false; }
  has "$s" 'per task'
  has "$s" 'tier'
  has "$s" 'fix round'
  has "$s" '(proof.s )?unit'
  has "$s" 'per phase'
  has "$s" 'per (open )?requirement'
  has "$s" 'ladder|falls back|fallback|fall back'
  has "$s" 'at least (3|three) finished|fewer than (3|three)'
}

@test "R191: docs/panel.md says side-by-side plans are not added, and how a proof's time comes from its units and the learned ratio" {
  local s
  s=$(section)
  has "$s" 'side by side|at the same time|in parallel'
  has "$s" 'longest|biggest|largest'
  has "$s" 'never (their )?sum|not (added|summed)'
  has "$s" 'runs\.json'
  has "$s" 'ratio'
}

@test "R191: docs/panel.md explains the road: its pieces, the usual fix rounds and their naming, and when there is no milestone end time yet" {
  local s
  s=$(section)
  has "$s" 'milestone end:'
  has "$s" 'wave'
  has "$s" 'qa'
  has "$s" 'fix rounds'
  has "$s" 'median'
  has "$s" 'rounded median of .outcome\.fix_rounds. over the latest 10 finished phases'
  has "$s" '1, 2, 2 and 5 give 2'
  has "$s" 'the usual here'
  has "$s" 'counting no fix rounds'
  has "$s" 'no milestone end time yet'
  has "$s" 'the rest follows once the work is planned|once the work is planned'
  ! printf '%s\n' "$s" | grep -q 'min left in the milestone' || { echo "the old milestone sentence is still described"; false; }
  ! printf '%s\n' "$s" | grep -q 'no estimate yet: there are not enough' || { echo "the old no-basis sentence is still described"; false; }
}

@test "R191: docs/panel.md says the history is this project's only, never shared across projects (D433)" {
  local s
  s=$(section)
  has "$s" 'this project|this clone'
  has "$s" 'not shared|never shared|no computer-wide|only this project|this project.s only|its own'
}

@test "R191: docs/next.md describes road with its fields and sentence" {
  grep -qF '`road`' "$NEXT" || grep -qF '"road"' "$NEXT" || { echo "docs/next.md does not describe road"; false; }
  for f in seconds end rounds basis say; do
    grep -qF "\"$f\"" "$NEXT" || grep -qF "\`$f\`" "$NEXT" || { echo "docs/next.md does not name road.$f"; false; }
  done
  grep -qF 'road.say' "$NEXT" || { echo "docs/next.md does not name road.say"; false; }
  grep -qiF 'no milestone end time yet' "$NEXT" || { echo "docs/next.md does not show the no-basis sentence"; false; }
  grep -qE 'latest 10 finished phases' "$NEXT" || { echo "docs/next.md does not give the rounds window"; false; }
  grep -qF 'Milestone end: about' "$NEXT" || { echo "docs/next.md shows no road sentence"; false; }
}

@test "R191: docs/statusline.md says the status line shows the step's time only, never the milestone's" {
  tr '\n' ' ' < "$STATUSLINE" | tr -s ' ' | grep -qiE "shows the step.s time only" \
    || { echo "docs/statusline.md does not say the status line shows the step's time only"; false; }
  tr '\n' ' ' < "$STATUSLINE" | tr -s ' ' | grep -qiE "milestone.{0,80}(mission control|panel|not|never|only)|(only|never|not).{0,80}milestone" \
    || { echo "docs/statusline.md does not say the status line leaves the milestone time to Mission Control"; false; }
}

@test "R191: docs/rigor.md says outcome.fix_rounds feeds the usual fix rounds of the milestone's end" {
  tr '\n' ' ' < "$RIGOR" | tr -s ' ' | grep -qiE 'fix_rounds.{0,150}.{0,150}(milestone.s end|milestone end|usual fix rounds|end of the milestone)' \
    || { echo "docs/rigor.md does not connect fix_rounds to the milestone's end"; false; }
  tr '\n' ' ' < "$RIGOR" | tr -s ' ' | grep -qiE 'rounded median of .fix_rounds. over the latest 10 finished phases of that tier \(at least 3 needed\)' \
    || { echo "docs/rigor.md does not give how the usual fix rounds are counted"; false; }
}

@test "R191: the README names the milestone's end where it describes the panel" {
  tr '\n' ' ' < "$README" | tr -s ' ' | grep -qiE "(mission control|panel).{0,200}.{0,200}(milestone.s end|milestone end|when the milestone should end|end of the milestone)" \
    || { echo "README.md does not name the milestone's end with the panel"; false; }
}
