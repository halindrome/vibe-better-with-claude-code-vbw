#!/usr/bin/env bash
# check-test-negations.sh FILE...: no test asserts with a negated command that
# cannot fail it. bash's errexit, which bats relies on, ignores a command
# negated with "!", so "! cmd" fails a test or a helper only as the last
# command of its block (a @test or a function), whose status is the block's.
# Anywhere else it must carry its own failure ("! cmd || false", "! cmd || {
# echo why; false; }"). Lines continued with a backslash count as one command;
# comments and here-document bodies are skipped. Refuses printing FILE:LINE:text
# and exits 1.
set -euo pipefail
[ $# -ge 1 ] || { printf 'usage: check-test-negations.sh FILE...\n' >&2; exit 2; }
status=0
for f in "$@"; do
  [ -f "$f" ] || { printf 'no file: %s\n' "$f" >&2; exit 2; }
  out=$(awk -v F="$f" '
    function flush() { if (pend != "") { print pend; pend = "" } }
    FNR == 1 { inblk = 0; pend = ""; doc = ""; cont = 0 }
    doc != "" { if ($0 ~ ("^[ \t]*" doc "[ \t]*$")) doc = ""; next }
    {
      line = $0
      start = !cont
      cont = (line ~ /\\$/)
      # A here-document starts after this line (never a here-string, <<<): skip its body.
      if (match(line, /(^|[^<])<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z_0-9]*/)) {
        d = substr(line, RSTART, RLENGTH); sub(/^[^<]?<<-?[ \t]*["\047]?/, "", d); doc = d
      }
      if (!start) {
        # The continuation of a negated command: a || on it gives the command its own failure.
        if (cand && line ~ /\|\|/) cand = 0
        if (!cont && cand) { pend = F ":" cl ":" ctext; cand = 0 }
        next
      }
      if (line ~ /^@test / || line ~ /^[A-Za-z_][A-Za-z_0-9]*\(\)[ \t]*\{[ \t]*$/) { inblk = 1; pend = ""; next }
      if (inblk && line ~ /^\}/) { inblk = 0; pend = ""; next }
      if (!inblk || line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
      flush()
      cand = (line ~ /^[ \t]*![ \t]/ && line !~ /\|\|/)
      if (cand && !cont) { pend = F ":" FNR ":" line; cand = 0 }
      else if (cand) { cl = FNR; ctext = line }
    }' "$f")
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    status=1
  fi
done
if [ "$status" -ne 0 ]; then
  printf 'a negated command that is not its block'"'"'s last never fails the test: add || false (or || { echo why; false; })\n' >&2
fi
exit "$status"
