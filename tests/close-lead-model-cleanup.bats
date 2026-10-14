#!/usr/bin/env bats
# R188 (L1, repository state): what D369 left behind is undone. The R186 tool
# that drove the closing step on Haiku and its committed results are gone, so
# nothing in tools/ claims a Haiku close; tests/profile-lead-opus.bats (C180,
# R119) checks again that every vbw:lead call of the balanced profile, the
# planning step and the closing step, runs on Opus, with its D369/D370 note
# gone; and a decision recorded after D370 marks D369 and D370 superseded.

load helper

RECORD="$REPO_ROOT/.vbw/record.json"

@test "R188: the R186 run tool and its results are gone: nothing in tools/ claims a Haiku close" {
  [ ! -e "$REPO_ROOT/tools/close-haiku-run.sh" ] || { echo "tools/close-haiku-run.sh is still there"; false; }
  [ ! -e "$REPO_ROOT/tools/baseline/results/close-haiku" ] || { echo "tools/baseline/results/close-haiku/ is still there"; false; }
  local hits
  hits=$(grep -rliE 'close-haiku|closing step (runs )?on haiku|haiku closing' "$REPO_ROOT/tools" || true)
  [ -z "$hits" ] || { echo "still claiming a Haiku close: $hits"; false; }
}

@test "R188: tests/profile-lead-opus.bats checks every vbw:lead call of the balanced planning run on opus, with no D369/D370 note" {
  local f="$REPO_ROOT/tests/profile-lead-opus.bats"
  [ -f "$f" ]
  if grep -nE 'D369|D370|closing step runs on Haiku' "$f"; then
    echo "tests/profile-lead-opus.bats still carries the D369/D370 note"
    false
  fi
  grep -qF '[.calls[] | select(.opts.agentType == "vbw:lead")] | length == 2 and all(.[]; .opts.model == "opus")' "$f" || {
    echo "tests/profile-lead-opus.bats does not check both Lead steps (planning and closing) on opus"
    false
  }
}

@test "R188: a decision recorded after D370 marks D369 and D370 superseded" {
  [ -f "$RECORD" ]
  jq -e '[.decisions[] | select((.id | ltrimstr("D") | tonumber) > 370)
      | select((.text | test("D369")) and (.text | test("D370")) and (.text | test("supersede"; "i")))] | length >= 1' "$RECORD" \
    || { echo "no decision after D370 marks D369 and D370 superseded"; false; }
}
