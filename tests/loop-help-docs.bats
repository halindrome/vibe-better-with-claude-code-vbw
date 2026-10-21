#!/usr/bin/env bats
# R178 (P127): vbw loop --help and vbw help list the command with its
# sub-commands and the three ceiling forms; docs/loop.md documents start, stop,
# status, the ceiling modes, the exact rule of the delegated approval and how
# it is recorded (the decision text and the consent entry); the record's format
# (plugin/lib/record.jq) validates the loop field and docs/record.md describes
# it. L1.

load helper
load loop-helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R178: vbw loop --help and vbw help list start, stop and status with the three ceiling forms" {
  run "$VBW" loop --help
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "usage: vbw loop"* ]]
  local w
  for w in "loop start" "loop stop" "loop status" "--ceiling USD" "--finish-item" "--no-ceiling"; do
    [[ "$output" == *"$w"* ]] || { echo "vbw loop --help lacks $w: $output"; false; }
  done
  run "$VBW" help
  [[ "$output" == *"loop start"* ]] && [[ "$output" == *"loop stop"* ]] && [[ "$output" == *"loop status"* ]] || { echo "$output"; false; }
  [[ "$output" == *"--ceiling USD"* ]] && [[ "$output" == *"--finish-item"* ]] && [[ "$output" == *"--no-ceiling"* ]] || { echo "$output"; false; }
}

@test "R178: docs/loop.md documents start, stop, status, the ceiling modes and the delegated approval rule and its records" {
  local f="$REPO_ROOT/docs/loop.md" w
  [ -f "$f" ]
  for w in "vbw loop start" "vbw loop stop" "vbw loop status" "--ceiling USD" "--finish-item" "--no-ceiling" \
           "approved by the loop on the user's behalf" "consent" "fingerprint" "vbw statusline on" "cannot tell" "baseline" "D317" "D315"; do
    grep -qF -- "$w" "$f" || { echo "docs/loop.md lacks: $w"; false; }
  done
  # The exact rule: every requirement's text equals one item's recorded text, each item once, nothing else but a carried [human] one.
  grep -qiE 'each item (matches|is matched) at most once|at most once' "$f"
  grep -qF '[human]' "$f"
}

@test "R178: docs/record.md describes the loop field and docs/costs.md the loop's spend" {
  grep -qF '| `loop` |' "$REPO_ROOT/docs/record.md"
  grep -qF 'baseline' "$REPO_ROOT/docs/record.md"
  grep -qF 'vbw loop' "$REPO_ROOT/docs/costs.md"
}

@test "R178: the record's format validates the loop field: a malformed loop is refused, a valid one is read" {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  "$VBW" status > /dev/null
  local bad
  for bad in '.loop = {}' '.loop.items = "T1"' '.loop.items[0].status = "flying"' '.loop.ceiling = {usd: -1, finish_item: false}' \
             '.loop.ceiling = {usd: 5}' '.loop.started_at = "yesterday"' '.loop.extra = 1' '.loop.items[0].id = "R1"' \
             '.loop.items[0].req = ""' '.loop.items[0].left = ""' '.loop.items[0].head = "abc"' '.loop.items[0].milestone = "X1"' \
             '.loop.items[0].retried = {fixes: []}' '.loop.items[0].reverts = [1]' '.loop.items[0].cost = {usd: -1, in: 0, out: 0}' \
             '.loop.items[0].reason = ""' '.loop.items[0].at = "soon"' '.loop.items[0].baseline = {s: {usd: 1}}' '.loop.items[0].unknown = 1' \
             '.loop.items[0].text = ""' '.loop.items[0].proof = "maybe"'; do
    edit_record "$bad"
    run "$VBW" status
    [ "$status" -eq 3 ] || { echo "accepted a malformed loop ($bad): $output"; false; }
    git checkout -q -- .vbw/record.json
    rm -f .vbw/runtime/glance.json
  done
  "$VBW" status > /dev/null
  # A valid item carrying every optional field (F196) is read.
  edit_record '.loop.items[0] += {milestone: "M2", req: "R2", head: ("0" * 40), baseline: {s1: {usd: 1, in: 10, out: 1, at: "2026-01-01T00:00:00Z"}},
    retried: {fixes: ["F1"], plans: []}, reverts: ["0123abc"], left: "4567def (does not revert cleanly)", cost: {usd: 1, in: 10, out: 1}, reason: "escalated twice", at: "2026-01-01T00:00:00Z"}'
  "$VBW" status > /dev/null
}
