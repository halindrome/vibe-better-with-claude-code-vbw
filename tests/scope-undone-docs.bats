#!/usr/bin/env bats
# R204: docs/proof.md step 4 of vbw prove states the exact-undo rule in plain
# words (what exact means, that git verifies it file by file, that an undo of
# an undo does not count, that the undoing commit is not judged either, that a
# partial or edited revert is still judged) and names the summary line;
# docs/record.md documents evidence.undone with its shape and the not-recorded
# case; docs/loop.md keeps the park's rule and says the loop's park and a hand
# revert now clear a commit the same way, so a scope violation parks an item
# only for a change that is still in the code. L1.

load helper

PROOF="$REPO_ROOT/docs/proof.md"
RECORD="$REPO_ROOT/docs/record.md"
LOOP="$REPO_ROOT/docs/loop.md"

# step4: the text of step 4 of the vbw prove list, up to step 5.
step4() { awk '/^## `vbw prove`/{on=1} on && /^4\. /{s=1} s && /^5\. /{exit} s' "$PROOF"; }

@test "R204: docs/proof.md step 4 no longer says a commit reverted by hand is still judged" {
  ! grep -qF 'A commit reverted by hand is still judged' "$PROOF" || { grep -n 'reverted by hand' "$PROOF"; false; }
}

@test "R204: docs/proof.md step 4 states the exact-undo rule in plain words and names the summary line" {
  local w
  [ -n "$(step4)" ] || { echo "no step 4 under ## vbw prove"; false; }
  for w in "exactly undone" "file by file" "mirror image" "an undo of an undo clears nothing" "the undoing commit is not judged either" "A partial or edited revert is still judged" "undone by" ", not judged"; do
    step4 | grep -qF -- "$w" || { echo "docs/proof.md step 4 lacks: $w"; step4; false; }
  done
  step4 | grep -qE 'scope: [0-9a-f]{12} \(P[0-9]+\.[0-9]+\) undone by [0-9a-f]{12}, not judged' || { step4; false; }
}

@test "R204: docs/record.md documents evidence.undone with its shape and the not-recorded case" {
  local row
  row=$(grep -F '| `evidence` |' "$RECORD")
  [ -n "$row" ] || { echo "no evidence row in docs/record.md"; false; }
  printf '%s\n' "$row" | grep -qF '`undone`' || { echo "$row"; false; }
  printf '%s\n' "$row" | grep -qF '{commit, plan, by}' || { echo "$row"; false; }
  printf '%s\n' "$row" | grep -qF '40' || { echo "$row"; false; }
  printf '%s\n' "$row" | grep -qF 'a record written before' || { echo "$row"; false; }
  printf '%s\n' "$row" | grep -qF '`[]` when none' || { echo "$row"; false; }
}

@test "R204: docs/loop.md keeps the park's rule and says a park and a hand revert clear a commit the same way" {
  grep -qF 'git revert' "$LOOP"
  grep -qF 'Reverts the item'"'"'s commits made since its milestone began, newest first' "$LOOP"
  grep -qiF 'a hand revert' "$LOOP" || { grep -n 'revert' "$LOOP"; false; }
  grep -qF 'clear a commit the same way' "$LOOP" || { grep -n 'the same way' "$LOOP"; false; }
  grep -qF 'still in the code' "$LOOP" || { grep -n 'in the code' "$LOOP"; false; }
}
