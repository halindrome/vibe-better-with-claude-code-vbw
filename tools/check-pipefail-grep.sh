#!/usr/bin/env bash
# check-pipefail-grep.sh DIR...: no shell code pipes printf or echo into a quiet
# grep (grep -q, -Eq, -qi, --quiet, --silent). grep -q exits at its first match
# and stops reading; a producer still writing then gets SIGPIPE, and under
# set -o pipefail (bin/vbw and every tool that sets it) the pipeline fails
# although the text matched. It needs input larger than the pipe (about 4 KB on
# macOS, 64 KB on Linux) to happen: a screen dump, a file list, a log. A short
# string passes today and breaks the day it grows. A grep that reads to the end
# (no -q, output to /dev/null) cannot: printf '%s' "$text" | grep PATTERN > /dev/null.
# On every shell file under each DIR (*.sh and bin/vbw) it refuses each line that
# has printf or echo, then a pipe into a quiet grep, printing FILE:LINE:text and
# exiting 1. Comment lines are not code. A producer that is not printf or echo (a
# function, a command) is the reviewer's to judge.
set -euo pipefail
[ $# -ge 1 ] || { printf 'usage: check-pipefail-grep.sh DIR...\n' >&2; exit 2; }
for d in "$@"; do
  [ -d "$d" ] || { printf 'no directory: %s\n' "$d" >&2; exit 2; }
done
found=""
while IFS= read -r -d '' path; do
  out=$(awk -v F="$path" '
    /^[ \t]*#/ { next }
    /(^|[^[:alnum:]_.-])(printf|echo)[ \t][^|]*\|[ \t]*(command[ \t]+)?grep[ \t]+(-[A-Za-z]+[ \t]+)*(-[A-Za-z]*q[A-Za-z]*|--quiet|--silent)([ \t]|$)/ {
      print F ":" NR ":" $0
    }' "$path")
  [ -z "$out" ] || found="$found$out"$'\n'
done < <(find "$@" -type f \( -name '*.sh' -o -path '*/bin/vbw' \) -print0 | sort -z)
if [ -n "$found" ]; then
  printf '%s' "$found"
  exit 1
fi
