#!/usr/bin/env bats
# R40 (docs/interview.md): when VBW proposes requirements and when it presents a
# plan for approval, it offers at most three suggestions matched to the user's
# level, each a yes or no the user may decline; an accepted one becomes a
# requirement or a recorded decision; a declined one is remembered in the
# project and never offered again. The declined list is the kernel's and runs for
# real; when and how many are offered is the suggest skill's text (L1).

load helper

SKILL="$PLUGIN_ROOT/skills/suggest/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
TRIAGE="$PLUGIN_ROOT/skills/triage/SKILL.md"
DOC="$REPO_ROOT/docs/interview.md"
TRIAGE_DOC="$REPO_ROOT/docs/triage.md"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
}

teardown() { vbw_teardown; }

@test "R40: a declined suggestion is recorded in the project record by the kernel and never offered again" {
  vbw_run suggest decline "Add a dark mode?"
  [ "$status" -eq 0 ]
  jq -e '(.project.declined | length) == 1 and .project.declined[0].text == "Add a dark mode?" and (.project.declined[0].at | test("^[0-9]{4}-"))' .vbw/record.json
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.declined == ["Add a dark mode?"]'
  vbw_run suggest list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Add a dark mode?"* ]]
}

@test "R40: declining the same text twice is deduplicated, even with other case or spacing" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  vbw_run suggest decline "Add a dark mode?"
  [ "$status" -eq 0 ]
  vbw_run suggest decline "  add A  DARK mode?  "
  [ "$status" -eq 0 ]
  jq -e '.project.declined | length == 1' .vbw/record.json
  "$VBW" suggest decline "Keep a changelog?" > /dev/null
  jq -e '.project.declined | length == 2' .vbw/record.json
}

@test "R40: a declined suggestion stays declined across sessions and milestones" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  jq '.requirements = [{id: "R1", text: "Visitors can read the page", proof: "auto", status: "proven", milestone: "M1"}]
    | .milestone.status = "shipped"
    | .shipped = [{id: "M1", title: "First milestone", at: "2026-01-01T00:00:00Z"}]' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" milestone start "Second" > /dev/null
  run env VBW_SESSION_ID=a-new-session "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.declined == ["Add a dark mode?"]'
}

@test "R40: a record from an older VBW (nothing declined) is read: none declined" {
  cp "$BATS_TEST_DIRNAME/fixtures/records/v1.json" .vbw/record.json
  vbw_run suggest list
  [ "$status" -eq 0 ]
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.declined == []'
}

@test "R40: the declined list is written only through the kernel's validated write path" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  jq '.project.declined = ["a plain string, not an entry"]' .vbw/record.json > "$TEST_ROOT/bad.json"
  cp "$TEST_ROOT/bad.json" .vbw/record.json
  vbw_run suggest list
  [ "$status" -eq 3 ]
  [[ "$output" == *"corrupt"* ]]
  vbw_run suggest decline ""
  [ "$status" -eq 2 ]
  vbw_run suggest nonsense
  [ "$status" -eq 2 ]
}

@test "R40: the record change is additive under project: no new top-level key, so older VBWs read the project or ask for a newer VBW" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  jq -e '((.schema == 1 and (keys - ["schema","project","milestone","requirements","checks","phases","plans","fixes","todos","decisions","commands","settings","evidence","lease","shipped","converted"] == [])) or .schema > 1) and (keys - ["schema","project","milestone","requirements","checks","phases","plans","fixes","todos","decisions","commands","settings","evidence","lease","shipped","converted"] - ["protected"] == [])' .vbw/record.json
  jq -e '(.project | keys | sort) == ["declined","name"]' .vbw/record.json
}

@test "R40: the suggest skill states its limit of three suggestions" {
  [ -f "$SKILL" ]
  grep -qx 'name: suggest' "$SKILL"
  grep -qE '^description: .{20,}$' "$SKILL"
  grep -qiE 'at most three' "$SKILL"
}

@test "R40: the skill names the commands for each answer: vbw spec add, vbw decide, vbw suggest decline" {
  grep -qF 'vbw spec add' "$SKILL"
  grep -qF 'vbw decide' "$SKILL"
  grep -qF 'vbw suggest decline' "$SKILL"
}

@test "R40: the skill reads the requirements and decisions to check for duplicates: vbw show requirements and vbw show decisions" {
  grep -qF 'vbw show requirements' "$SKILL"
  grep -qF 'vbw show decisions' "$SKILL"
}

# step_text NAME: the router's text for step **NAME**, up to the next step.
step_text() {
  awk -v s="$1" 'index($0, "**" s "**") == 1 { on = 1; print; next } /^\*\*[A-Za-z]/ { on = 0 } /^## / { on = 0 } on' "$ROUTER"
}

@test "R40, R229: the router offers suggestions at spec proposal, at plan approval and right after triage adds work, and nowhere else" {
  [ "$(grep -cF 'vbw:suggest' "$ROUTER")" -ge 2 ]
  step_text spec | grep -qF 'vbw:suggest'
  step_text approve | grep -qF 'vbw:suggest'
  sed -n '/^## Outcomes/,/^## /p' "$TRIAGE" | grep -qF 'vbw:suggest'
  local step
  for step in build fix qa prove run; do
    if step_text "$step" | grep -qF 'vbw:suggest'; then echo "suggestions offered at $step"; false; fi
  done
}

# R229 (#734): suggestions come when a yes is free (spec proposal; right after triage adds
# requirements to the active milestone, before the first planning run) and at plan
# approval, where a yes that adds a requirement costs a new planning run: the question
# states that cost from detail.replan of vbw next --json and offers add to the backlog
# (Recommended, vbw todo add), add to this milestone (replan: vbw spec add, planning
# again, a new approval) or no (vbw suggest decline). A choice or constraint (vbw decide)
# costs no replan and keeps Yes/No, as do the two free moments. L1: the skills' words.

# flat FILE: the file on one line, lower case, spaces squeezed.
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

@test "R229: the suggest skill names its three moments, in the description and under When, and still never offers mid-run" {
  grep -E '^description:' "$SKILL" | grep -qi 'triage'
  grep -E '^description:' "$SKILL" | grep -qi 'approval'
  sed -n '/^## When/,/^## /p' "$SKILL" | tr '\n' ' ' | grep -qi 'triage'
  sed -n '/^## When/,/^## /p' "$SKILL" | tr '\n' ' ' | grep -qi 'before the first planning run'
  sed -n '/^## When/,/^## /p' "$SKILL" | tr '\n' ' ' | grep -qi 'never[^.]*mid-run, mid-build'
}

@test "R229: at plan approval a suggestion that adds a requirement is priced from detail.replan and offers the backlog (Recommended), the milestone (replan) or no" {
  grep -qF 'detail.replan' "$SKILL"
  flat "$SKILL" | grep -qE 'backlog[^.]{0,60}\(recommended\)|\(recommended\)[^.]{0,60}backlog'
  flat "$SKILL" | grep -q 'replan'
  grep -qE 'vbw todo add --sort next --size <small\|medium\|large>' "$SKILL"
  flat "$SKILL" | grep -qE 'a new planning run'
  flat "$SKILL" | grep -qE 'vbw decide[^.]{0,120}no replan|no replan[^.]{0,120}vbw decide'
  flat "$SKILL" | grep -qE '(spec proposal|after triage)[^.]{0,160}(costs nothing|free)'
}

@test "R229: the router's approve step passes detail.replan to vbw:suggest as the cost of a yes" {
  step_text approve | tr '\n' ' ' | grep -qE 'vbw:suggest[^.]{0,120}detail\.replan|detail\.replan[^.]{0,120}vbw:suggest'
}

@test "R229 docs: docs/interview.md's Suggestions name the three moments and the priced yes with the backlog recommended; docs/triage.md's now outcome names the suggestions" {
  local sec
  sec=$(sed -n '/^## Suggestions/,/^## /p' "$DOC" | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]')
  printf '%s' "$sec" | grep -q 'triage' || { echo "docs/interview.md does not name the after-triage moment"; false; }
  printf '%s' "$sec" | grep -q 'approval' || { echo "docs/interview.md does not name plan approval"; false; }
  printf '%s' "$sec" | grep -q 'backlog' || { echo "docs/interview.md does not name the backlog option"; false; }
  printf '%s' "$sec" | grep -qE 'planning run|replan' || { echo "docs/interview.md does not name the cost of a yes at approval"; false; }
  printf '%s' "$sec" | grep -q 'vbw todo add' || { echo "docs/interview.md does not name vbw todo add"; false; }
  printf '%s' "$sec" | grep -qE 'backlog[^-]{0,30}recommended' || { echo "docs/interview.md does not recommend the backlog"; false; }
  ! printf '%s' "$sec" | grep -q 'two moments' || { echo "docs/interview.md still says two moments"; false; }
  flat "$TRIAGE_DOC" | grep -qE 'now[^|]{0,200}suggest' || { echo "docs/triage.md's now outcome does not name the suggestions"; false; }
}
