#!/usr/bin/env bats
# R149: a write on a record larger than 2 MB leaves .vbw/record.json valid
# JSON holding the change and every earlier entry, byte for byte the same
# apart from the change (no truncation), and the commits it makes hold only
# the record and the files the command names, exactly as on the small twin
# (big-record-helper.bash). L1.

load helper
load big-record-helper

setup() {
  vbw_setup
  twins
}

teardown() { vbw_teardown; }

# snapshot: keep both twins' records and HEADs before a write.
snapshot() {
  cp "$SMALL/.vbw/record.json" "$TEST_ROOT/small.before.json"
  cp "$BIG/.vbw/record.json" "$TEST_ROOT/big.before.json"
  SMALL_HEAD=$(git -C "$SMALL" rev-parse HEAD)
  BIG_HEAD=$(git -C "$BIG" rev-parse HEAD)
}

# commits DIR SINCE: each commit after SINCE as one line of its sorted files.
commits() {
  local c
  for c in $(git -C "$1" rev-list --reverse "$2..HEAD"); do
    git -C "$1" show --name-only -z --format= "$c" | tr '\0' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' '
    printf '\n'
  done
}

# same_commits ALLOWED...: both twins made the same commits since the
# snapshot, and every file in them is one of ALLOWED.
same_commits() {
  local s b f
  s=$(commits "$SMALL" "$SMALL_HEAD")
  b=$(commits "$BIG" "$BIG_HEAD")
  [ "$s" = "$b" ] || { printf 'commits differ\nsmall:\n%s\nlarge:\n%s\n' "$s" "$b"; return 1; }
  for f in $b; do
    case " $* " in *" $f "*) ;; *) echo "the commit holds $f, which the command did not name"; return 1 ;; esac
  done
}

# kept FILTER: the large twin's record is valid JSON, and FILTER applied to it
# gives back exactly the record before the write (nothing lost or cut). The
# schema and the protected field are left out of the comparison: the writer
# sets both from the fields in use (R46, R150), and the twins' 102 checks give
# a write the protected field.
kept() {
  jq -e . "$BIG/.vbw/record.json" > /dev/null || { echo "the record is not valid JSON"; return 1; }
  [ "$(jq -cS "($1) | del(.schema, .protected)" "$BIG/.vbw/record.json")" = "$(jq -cS 'del(.schema, .protected)' "$TEST_ROOT/big.before.json")" ] \
    || { echo "the record lost or changed more than the write: $1"; return 1; }
  [ "$(wc -c < "$BIG/.vbw/record.json")" -gt 2097152 ]
}

# committed: when the record was committed, the commit holds it whole.
committed() {
  git -C "$BIG" diff --quiet HEAD -- .vbw/record.json || return 0
  git -C "$BIG" show HEAD:.vbw/record.json | cmp -s - "$BIG/.vbw/record.json"
}

@test "R149: vbw decide on a record over 2 MB keeps every earlier entry and commits as on a small record" {
  snapshot
  twin_step decide "Keep the history" "the owner wants it"
  kept 'del(.decisions[-1])'
  jq -e '.decisions[-1] | .text == "Keep the history" and .why == "the owner wants it"' "$BIG/.vbw/record.json"
  jq -e '.decisions[-2].text | length > 131072' "$BIG/.vbw/record.json"
  same_commits .vbw/record.json
  committed
}

@test "R149: vbw todo add on a record over 2 MB keeps every earlier entry and commits only the record" {
  snapshot
  twin_step todo add "Gift cards"
  kept 'del(.todos[-1])'
  jq -e '.todos[-1] | .text == "Gift cards" and .status == "open"' "$BIG/.vbw/record.json"
  same_commits .vbw/record.json
  committed
  [ -z "$(git -C "$BIG" status --porcelain -- .vbw/record.json)" ]
}

@test "R149: vbw req accept on a record over 2 MB changes only the requirement's status and commits as on a small record" {
  snapshot
  twin_step req accept R53
  kept '(.requirements[] | select(.id == "R53") | .status) = "open"'
  jq -e '.requirements[] | select(.id == "R53") | .status == "accepted"' "$BIG/.vbw/record.json"
  same_commits .vbw/record.json
  committed
}

@test "R149: apply, approve and vbw commit on a record over 2 MB commit only the record, the check files and the plan's files, as on a small record" {
  twin_doc > "$TEST_ROOT/doc.json"
  snapshot
  TWIN_IN="$TEST_ROOT/doc.json" twin_step apply
  kept 'del(.phases[-2:], .plans[-2:], .checks[-2:]) | (.requirements[] | select(.milestone == "M2")) |= del(.rules)
    | (.phases[] |= del(.proposed, .reasons, .predicted))'
  twin_step approve
  same_commits .vbw/record.json .vbw/spec.md tests/a.sh tests/b.sh
  committed
  snapshot
  twin_step run start build P51.1 P52.1
  in_twins sh -c 'printf "a\n" > src/a.txt && printf "x\n" > notes.txt'
  twin_step commit P51.1 "feat(p51): part a"
  same_commits src/a.txt .vbw/record.json
  [ -n "$(git -C "$BIG" status --porcelain -- notes.txt)" ]
  twin_step plan "done" P51.1
  jq -e '.plans[] | select(.id == "P51.1") | .status == "done"' "$BIG/.vbw/record.json"
  [ "$(jq '[.plans[] | select(.status == "done")] | length' "$BIG/.vbw/record.json")" -eq 101 ]
  [ "$(jq '.decisions | length' "$BIG/.vbw/record.json")" -ge 121 ]
}
