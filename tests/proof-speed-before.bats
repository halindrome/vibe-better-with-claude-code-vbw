#!/usr/bin/env bats
# R202 (VBW's own record): the before numbers of this milestone, taken on this
# Mac with tools/measure-proof-speed.sh at its default size before any speed
# fix, are a decision in the record (vbw decide). The decision names the
# stand-in's size, the proof's wall time and own-work share, the units reused
# after the one-file change, the jq CPU seconds and process count, the store
# and written-list sizes, the time vbw next --json took, the five own-work
# steps, and confirms or clears each suspect found by reading the code:
# (a) the per-folder fingerprint work in reads_collect, (b) build-cache files
# inflating the written-file lists, (c) the store and record parsed per unit,
# (d) vbw next redoing the proof's reuse planning. The record is read as
# committed. L1.

load helper

RECORD="$REPO_ROOT/.vbw/record.json"

# before: the text of the before decision (the latest one, when several).
before() { jq -r '[.decisions[] | select(.text | startswith("Proof speed before (M42) on this Mac:"))] | last | .text // empty' "$RECORD"; }

# has RE: the decision's text matches RE.
has() { printf '%s\n' "$(before)" | grep -Eq -- "$1" || { echo "the before decision lacks /$1/:"; before; return 1; }; }

@test "R202: the before decision is recorded with the stand-in's size and every figure" {
  [ -n "$(before)" ] || { echo "no decision starts with 'Proof speed before (M42) on this Mac:'"; false; }
  has 'stand-in \([0-9]+ files, [0-9]+ folders, [0-9]+ units\)'
  has 'prove [0-9]+(\.[0-9]+)? s wall'
  has 'own work [0-9]+(\.[0-9]+)? s \([0-9]+%\)'
  has 'fix done after one file: reused [0-9]+ of [0-9]+ units'
  has 'jq [0-9]+(\.[0-9]+)? CPU s in [0-9]+ processes'
  has 'store [0-9]+ bytes'
  has 'written lists [0-9]+ bytes'
  has 'vbw next [0-9]+(\.[0-9]+)? s'
}

@test "R202: the before decision names the time of each own-work step" {
  has 'planning [0-9]+(\.[0-9]+)? s'
  has 'copies [0-9]+(\.[0-9]+)? s'
  has 'read tracking [0-9]+(\.[0-9]+)? s'
  has 'saving [0-9]+(\.[0-9]+)? s'
  has 'record [0-9]+(\.[0-9]+)? s'
}

@test "R202: the before decision confirms or clears each of the four suspects" {
  has '\(a\) (confirmed|cleared)'
  has '\(b\) (confirmed|cleared)'
  has '\(c\) (confirmed|cleared)'
  has '\(d\) (confirmed|cleared)'
}
