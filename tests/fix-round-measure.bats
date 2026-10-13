#!/usr/bin/env bats
# R182 (tools/measure-fix-round.sh, VBW's own record): measure first. The tool
# builds one fixture project and runs one fix round on it, either as every Dev
# did before (per-group: each group's own vbw fix done, all at once) or as the
# workflow does now (round: one vbw fix done for every group), and prints the
# wall-clock minutes, the checks and test files run, and how many ran more than
# once. VBW's record holds the measurement taken before the change as a
# decision, and a later decision that supersedes it with the same figures, the
# figures after the change (0 ran more than once), the chosen approach and the
# rejected one (a kernel lock), and the reasons. The record is read as
# committed: the run that records the decisions commits it when it ends. L1.

load helper

TOOL="$REPO_ROOT/tools/measure-fix-round.sh"
RECORD="$REPO_ROOT/.vbw/record.json"

BEFORE_RE='^Fix round before the change: fixture tools/measure-fix-round\.sh \(([^)]+)\), 3 groups, each Dev its own vbw fix done: ([0-9]+(\.[0-9]+)?) minutes, ([0-9]+) checks and ([0-9]+) test files run, ([0-9]+) ran more than once$'
AFTER_HEAD='^Supersedes D[0-9]+: one vbw fix done per fix round, run by the workflow after every Dev returns\. '

# measure MODE GROUPS: run the tool on a fresh fixture with instant checks.
measure() {
  VBW_MEASURE_DIR="$TEST_ROOT/measure" VBW_MEASURE_SECONDS=0 run bash "$TOOL" "$@" < /dev/null
}

# field NAME: the value of the "NAME: value" line of the last output.
field() { printf '%s\n' "$output" | sed -n "s/^$1: //p"; }

@test "R182: the tool measures a round run as one vbw fix done: its minutes, checks and test files run, and 0 ran more than once" {
  vbw_setup
  measure round 3
  [ "$status" -eq 0 ] || { echo "$output"; vbw_teardown; false; }
  [ -n "$(field fixture)" ] && [ "$(field mode)" = round ] && [ "$(field groups)" = 3 ] || { echo "$output"; vbw_teardown; false; }
  [[ "$(field minutes)" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "$output"; vbw_teardown; false; }
  [[ "$(field 'checks run')" =~ ^[0-9]+$ ]] && [ "$(field 'checks run')" -gt 0 ] || { echo "$output"; vbw_teardown; false; }
  [[ "$(field 'test files run')" =~ ^[0-9]+$ ]] || { echo "$output"; vbw_teardown; false; }
  [ "$(field 'ran more than once')" = 0 ] || { echo "$output"; vbw_teardown; false; }
  vbw_teardown
}

@test "R182: the tool measures a round where each group runs its own vbw fix done at the same time" {
  vbw_setup
  measure per-group 3
  [ "$status" -eq 0 ] || { echo "$output"; vbw_teardown; false; }
  [ "$(field mode)" = per-group ] && [ "$(field groups)" = 3 ] || { echo "$output"; vbw_teardown; false; }
  [[ "$(field minutes)" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "$output"; vbw_teardown; false; }
  [[ "$(field 'checks run')" =~ ^[0-9]+$ ]] && [ "$(field 'checks run')" -gt 0 ] || { echo "$output"; vbw_teardown; false; }
  [[ "$(field 'test files run')" =~ ^[0-9]+$ ]] || { echo "$output"; vbw_teardown; false; }
  [[ "$(field 'ran more than once')" =~ ^[0-9]+$ ]] || { echo "$output"; vbw_teardown; false; }
  vbw_teardown
}

@test "R182: the tool refuses a missing or unknown mode and a group count below 1" {
  vbw_setup
  measure
  [ "$status" -eq 2 ] && [[ "$output" == *usage* ]] || { echo "$output"; vbw_teardown; false; }
  measure sideways 3
  [ "$status" -eq 2 ] && [[ "$output" == *usage* ]] || { echo "$output"; vbw_teardown; false; }
  measure round 0
  [ "$status" -eq 2 ] && [[ "$output" == *usage* ]] || { echo "$output"; vbw_teardown; false; }
  vbw_teardown
}

@test "R182: VBW's record holds the measurement taken before the change, naming the fixture and its figures" {
  jq -e --arg re "$BEFORE_RE" 'any(.decisions[]; .text | test($re))' "$RECORD" > /dev/null || {
    echo "no decision of the form: Fix round before the change: fixture tools/measure-fix-round.sh (...), 3 groups, each Dev its own vbw fix done: X minutes, N checks and M test files run, K ran more than once"
    false
  }
}

@test "R182: a later decision supersedes the before measurement with the same fixture and figures, and the after figures with 0 ran more than once" {
  jq -e --arg re "$AFTER_HEAD" 'any(.decisions[]; .text | test($re))' "$RECORD" > /dev/null || { echo "no decision starting: Supersedes D<n>: one vbw fix done per fix round, ..."; false; }
  jq -e --arg head "$AFTER_HEAD" --arg bre "$BEFORE_RE" '
    .decisions as $all
    | [$all[] | select(.text | test($head))] | last as $a
    | ($a.text | capture("^Supersedes (?<id>D[0-9]+): ").id) as $bid
    | ([$all[] | select(.id == $bid)][0] // {text: ""}) as $b
    | ($b.text | test($bre)) as $isbefore
    | if $isbefore | not then false else
        ($b.text | capture("fixture tools/measure-fix-round\\.sh \\((?<p>[^)]+)\\)").p) as $bp
        | ($b.text | capture("each Dev its own vbw fix done: (?<f>.*)$").f) as $bf
        | (($bid | ltrimstr("D") | tonumber) < ($a.id | ltrimstr("D") | tonumber))
          and ($a.text | contains("Fixture tools/measure-fix-round.sh (" + $bp + "), 3 groups. "))
          and ($a.text | contains("Before, each Dev its own vbw fix done: " + $bf + ". "))
          and ($a.text | test("After, one vbw fix done per round: [0-9]+(\\.[0-9]+)? minutes, [0-9]+ checks and [0-9]+ test files run, 0 ran more than once\\."))
      end' "$RECORD" > /dev/null || {
    jq -r --arg head "$AFTER_HEAD" '[.decisions[] | select(.text | test($head))] | last | "\(.id) \(.text)"' "$RECORD"
    false
  }
}

@test "R182: the decision names the chosen approach and the rejected kernel lock, with reasons drawn from the measurement" {
  jq -e --arg head "$AFTER_HEAD" '
    [.decisions[] | select(.text | test($head))] | last as $a
    | ($a != null)
    and ($a.text | test("Rejected: a kernel lock that makes vbw fix done runs in one clone wait for each other"))
    and (($a.why // "") | test("lock"; "i"))
    and (($a.why // "") | test("one vbw fix done|one fix done"; "i"))
    and (($a.why // "") | test("[0-9]+(\\.[0-9]+)? minutes"))' "$RECORD" > /dev/null || {
    jq -r --arg head "$AFTER_HEAD" '[.decisions[] | select(.text | test($head))] | last | "\(.id) \(.text) (why: \(.why))"' "$RECORD"
    false
  }
}
