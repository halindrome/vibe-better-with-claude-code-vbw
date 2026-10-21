#!/usr/bin/env bats
# R202 (VBW's own record): the after numbers of this milestone, taken on the
# same Mac with the same tool (tools/measure-proof-speed.sh, default size)
# once the speed fixes and the bookkeeping slots were in, are a decision in
# the record (vbw decide), in the before decision's form plus the expected
# reuse count and the two-proof sample. The targets the phase sets are read
# from it: VBW's own work for the whole proof under 60 s, read tracking under
# 1 s per unit, jq CPU under 60 s, vbw next --json under 5 s with the store
# full, the units reused after the one-file change equal to the units whose
# read lists do not contain the changed file, and two proofs at once never
# holding more than the machine limit. The record is read as committed. L1.

load helper

RECORD="$REPO_ROOT/.vbw/record.json"

after() { jq -r '[.decisions[] | select(.text | startswith("Proof speed after (M42) on this Mac:"))] | last | .text // empty' "$RECORD"; }

# num RE: the first number captured by RE in the decision's text.
num() {
  local v
  v=$(printf '%s\n' "$(after)" | sed -nE "s/.*$1.*/\\1/p" | head -n 1)
  [ -n "$v" ] || { echo "the after decision lacks /$1/:"; after; return 1; }
  printf '%s\n' "$v"
}

# below VALUE LIMIT: VALUE < LIMIT (decimals allowed).
below() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 < b + 0) }'; }

@test "R202: the after decision is recorded in the before decision's form" {
  [ -n "$(after)" ] || { echo "no decision starts with 'Proof speed after (M42) on this Mac:'"; false; }
  num 'stand-in \(([0-9]+) files' > /dev/null
  num 'prove ([0-9]+(\.[0-9]+)?) s wall' > /dev/null
  num 'store ([0-9]+) bytes' > /dev/null
  num 'written lists ([0-9]+) bytes' > /dev/null
  num 'planning ([0-9]+(\.[0-9]+)?) s' > /dev/null
  num 'copies ([0-9]+(\.[0-9]+)?) s' > /dev/null
  num 'saving ([0-9]+(\.[0-9]+)?) s' > /dev/null
  num 'record ([0-9]+(\.[0-9]+)?) s' > /dev/null
}

@test "R202: own work under 60 s, read tracking under 1 s per unit, jq CPU under 60 s, vbw next under 5 s" {
  local own units tracking cpu next
  own=$(num 'own work ([0-9]+(\.[0-9]+)?) s')
  units=$(num 'stand-in \([0-9]+ files, [0-9]+ folders, ([0-9]+) units\)')
  tracking=$(num 'read tracking ([0-9]+(\.[0-9]+)?) s')
  cpu=$(num 'jq ([0-9]+(\.[0-9]+)?) CPU s')
  next=$(num 'vbw next ([0-9]+(\.[0-9]+)?) s')
  [ "$units" -ge 200 ] || { echo "the after run used $units units, under the 200 of the stand-in"; false; }
  below "$own" 60 || { echo "own work $own s is not under 60 s"; false; }
  below "$(awk -v t="$tracking" -v u="$units" 'BEGIN { print t / u }')" 1 || { echo "read tracking $tracking s over $units units is not under 1 s per unit"; false; }
  below "$cpu" 60 || { echo "jq CPU $cpu s is not under 60 s"; false; }
  below "$next" 5 || { echo "vbw next $next s is not under 5 s"; false; }
}

@test "R202: the units reused after the one-file change equal the units whose read lists do not contain the changed file" {
  local reused expected
  reused=$(num 'fix done after one file: reused ([0-9]+) of [0-9]+ units \(expected [0-9]+\)')
  expected=$(num 'fix done after one file: reused [0-9]+ of [0-9]+ units \(expected ([0-9]+)\)')
  [ "$reused" -eq "$expected" ] || { echo "reused $reused, expected $expected"; false; }
  [ "$expected" -gt 0 ]
}

@test "R202: two proofs at once never held more than the machine limit" {
  local held limit
  held=$(num 'two proofs: max held ([0-9]+) of limit [0-9]+')
  limit=$(num 'two proofs: max held [0-9]+ of limit ([0-9]+)')
  [ "$held" -ge 1 ] && [ "$held" -le "$limit" ] || { echo "max held $held, limit $limit"; false; }
}
