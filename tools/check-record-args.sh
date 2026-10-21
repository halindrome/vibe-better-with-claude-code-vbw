#!/usr/bin/env bash
# check-record-args.sh DIR...: no shell code passes record-sized data to jq as
# a command-line argument (R149). A command line is capped by the operating
# system (about 1 MB), and a long-lived project's record is larger.
# On every non-comment line of the shell files under each DIR (*.sh and
# bin/vbw) it looks at what follows the first --arg, --argjson, --args,
# --jsonargs or here-string (<<<) and refuses, printing FILE:LINE:text and
# exiting 1: record_read, qa_combined, qa_digests, qa_state, qa_cache_read, a
# cat or git show of record.json (or VBW_RECORD), a variable named record,
# record_json, digests or results, a list that grows with the project (the
# variables units, causes and TF_REUSE: Linux caps one argument at 128 KB, about
# 3,000 test files), and a positional parameter ($1, ${2}, ...) that the
# function's header comment ("# name ARG...: ...") names RECORD, RECORD_JSON,
# DIGESTS, RESULTS or UNITS. Data written into a pipe first
# (printf '%s' "$record" | jq ...), --slurpfile, --rawfile, small values and
# comments pass. A <(...) handed to --slurpfile or --rawfile is a file and passes
# too, unless a jq --arg... or a here-string inside it takes the data.
set -euo pipefail
[ $# -ge 1 ] || { printf 'usage: check-record-args.sh DIR...\n' >&2; exit 2; }
for d in "$@"; do
  [ -d "$d" ] || { printf 'no directory: %s\n' "$d" >&2; exit 2; }
done
status=0
while IFS= read -r -d '' path; do
  out=$(awk -v F="$path" '
    function positional(n) { return (n in posn) }
    {
      line = $0
      if (line ~ /^[ \t]*#/) {
        # Header comment "# name ARG...: ...": remember which positions are record-sized.
        h = line; sub(/^[ \t]*#[ \t]+/, "", h)
        if (h ~ /^[a-z_][a-z_0-9]*[ \t]+[^:]*:/) {
          split(h, w, /[ \t]+/)
          pend = w[1]; delete pending
          for (i = 2; i in w; i++) {
            t = w[i]; stop = (t ~ /:/)
            gsub(/[\[\]:.]/, "", t)
            if (t == "RECORD" || t == "RECORD_JSON" || t == "DIGESTS" || t == "RESULTS" || t == "UNITS") pending[i - 1] = 1
            if (stop) break
          }
        }
        next
      }
      if (line ~ /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z_0-9]*[ \t]*\(\)/) {
        n = line; sub(/^[ \t]*(function[ \t]+)?/, "", n); sub(/[ \t]*\(\).*/, "", n)
        delete posn
        if (n == pend) for (k in pending) posn[k] = 1
        pend = ""; delete pending
      }
      if (line ~ /^}/) delete posn
      if (!match(line, /(--arg|--argjson|--args|--jsonargs)([ \t]|$)|<<</)) next
      tail = substr(line, RSTART)
      # data written into a pipe is how it must be done
      gsub(/(printf[ \t]+(\047%s\047|"%s"|%s)|echo)[ \t]+"?\$\{?(record|record_json|digests|results|units|causes|TF_REUSE)\}?"?[ \t]*\|/, "", tail)
      # a process substitution handed to --slurpfile or --rawfile is a file, not an argument, unless
      # a command inside it takes the data as one (jq --arg ... or a here-string): that part is judged
      rest = tail; tail = ""
      while (match(rest, /--(slurpfile|rawfile)[ \t]+[A-Za-z_][A-Za-z_0-9]*[ \t]+<\([^)]*\)/)) {
        ps = substr(rest, RSTART, RLENGTH)
        tail = tail substr(rest, 1, RSTART - 1)
        if (ps ~ /(--arg|--argjson|--args|--jsonargs)([ \t]|$)|<<</) tail = tail ps
        rest = substr(rest, RSTART + RLENGTH)
      }
      tail = tail rest
      bad = 0
      if (tail ~ /record_read|qa_combined|qa_digests|qa_state|qa_cache_read/) bad = 1
      if (tail ~ /(cat|git show)[^|]*(record\.json|VBW_RECORD)/) bad = 1
      if (tail ~ /\$\{?(record|record_json|digests|results|units|causes|TF_REUSE)\}?([^A-Za-z0-9_]|$)/) bad = 1
      for (k in posn) if (tail ~ ("\\$\\{?" k "([^0-9A-Za-z_]|$)")) bad = 1
      if (bad) printf "%s:%d:%s\n", F, NR, line
    }' "$path")
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    status=1
  fi
done < <(for d in "$@"; do find "$d" -type f \( -name '*.sh' -o -name vbw \) -print0; done)
if [ "$status" -ne 0 ]; then
  printf 'record-sized data on a command line: send it through a pipe, --slurpfile or --rawfile\n' >&2
fi
exit "$status"
