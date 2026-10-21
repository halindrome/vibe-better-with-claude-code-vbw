#!/usr/bin/env bash
# check-loop-writes.sh DIR...: no shell code writes with a builtin (printf or
# echo) in the shell that runs a loop fed by a process substitution
# (while ...; done < <(PRODUCER)). The producer is a live child of that shell
# for as long as the loop runs. macOS /bin/bash 3.2 catches SIGCHLD without
# SA_RESTART (bash 4.2 added it), so a builtin write there that waits for a
# slow reader (a full pipe: Claude Code's Bash tool, a terminal, bats) fails
# with EINTR when the producer exits, and what it was writing is lost
# ("write error: Interrupted system call"; under set -e the command fails).
# Inside such a loop a write passes when it runs in a child of its own (through
# vbw_out in core.sh, in a command substitution, a subshell, a pipeline or a
# loop fed by a pipe) or goes into a file (> or >>). Or the producer is piped
# into the loop (PRODUCER | while ...), so the loop's shell has no child.
# On every shell file under each DIR (*.sh and bin/vbw) it finds each loop fed
# by a process substitution (the done that closes it, then < <(, on its line or
# the next) and its start (the same line, or the nearest line above at the same
# indentation, which must open a while, until or for loop), and refuses each
# builtin write in between, printing FILE:LINE:text and exiting 1. A loop whose
# start it cannot find is refused too. Quoted text, comments and here-documents
# are not code. A function the body calls writes in the same shell and is not
# seen: such a call is the reviewer's to judge.
set -euo pipefail
[ $# -ge 1 ] || { printf 'usage: check-loop-writes.sh DIR...\n' >&2; exit 2; }
for d in "$@"; do
  [ -d "$d" ] || { printf 'no directory: %s\n' "$d" >&2; exit 2; }
done
found=""
while IFS= read -r -d '' path; do
  out=$(awk -v F="$path" '
    # strip(s): s with every quoted run blanked (the same length) and a comment
    # cut off; QS carries a quote left open into the next line.
    function strip(s,    o, i, c, n) {
      o = ""; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (QS == "s") { if (c == "\047") { QS = ""; o = o c } else o = o " "; continue }
        if (QS == "a" || QS == "d") {
          if (c == "\\") { o = o "  "; i++; continue }
          if ((QS == "a" && c == "\047") || (QS == "d" && c == "\"")) { QS = ""; o = o c } else o = o " "
          continue
        }
        if (c == "\\") { o = o substr(s, i, 2); i++; continue }
        if (c == "\047") { QS = (i > 1 && substr(s, i - 1, 1) == "$") ? "a" : "s"; o = o c; continue }
        if (c == "\"") { QS = "d"; o = o c; continue }
        if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;&|()]/)) break
        o = o c
      }
      return o
    }
    function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
    # open(s): how many parentheses s leaves open (a substitution or a subshell).
    function open(s,    i, c, d) {
      d = 0
      for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == "(") d++; else if (c == ")" && d > 0) d-- }
      return d
    }
    # simple(s): s up to the end of its simple command (a ; && || or an unmatched
    # ) or }), the insides of ${...} and (...) blanked, >( marked P.
    function simple(s,    o, i, c, nx, dp, db) {
      o = ""; dp = 0; db = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        if (c == "$" && nx == "{") { db++; o = o "  "; i++; continue }
        if (c == ">" && nx == "(" && dp == 0 && db == 0) { dp++; o = o ">P"; i++; continue }
        if (c == "(") { dp++; o = o " "; continue }
        if (c == ")") { if (dp == 0) break; dp--; o = o " "; continue }
        if (c == "}") { if (db == 0) break; db--; o = o " "; continue }
        if (dp > 0 || db > 0) { o = o " "; continue }
        if (c == ";" || (c == "&" && nx == "&") || (c == "|" && nx == "|")) break
        o = o c
      }
      return o
    }
    # writes(t, ln): mark line ln when the code text t holds a builtin write
    # that runs in the loop shell itself.
    function writes(t, ln,    rest, pre, seg) {
      rest = t
      while (match(rest, /(printf|echo)([ \t]|$)/)) {
        pre = substr(t, 1, length(t) - length(rest) + RSTART - 1)
        seg = substr(rest, RSTART + RLENGTH)
        rest = seg
        # Part of a longer word (sprintf, vbw_echo), never the command itself.
        if (pre != "" && substr(pre, length(pre), 1) ~ /[A-Za-z0-9_.\/-]/) continue
        sub(/[ \t]+$/, "", pre)
        # Only a command, never an argument (command -v printf).
        if (pre != "" && pre !~ /[;&|({!]$/ && pre !~ /(^|[ \t])(then|do|else|if|while|until|elif)$/) continue
        # In a child: a command or process substitution, a subshell, a later pipeline stage.
        if (open(pre) > 0 || (pre ~ /\|$/ && pre !~ /\|\|$/)) continue
        seg = simple(seg)
        # The first stage of a pipeline runs in a child.
        if (seg ~ /\|/) continue
        # Duplicated descriptors (>&2, 2>&1) and redirections of other descriptors write nothing of its own.
        gsub(/[0-9]*>>?[ \t]*&[0-9-]*/, "", seg)
        gsub(/[02-9]>>?[ \t]*[^ \t]*/, "", seg)
        # &> FILE, or a job of its own in the background.
        if (seg ~ /&/) continue
        # Its output into a file (never into a process substitution).
        if (seg ~ />/ && seg !~ />>?[ \t]*>P/) continue
        bad[ln] = 1
      }
    }
    {
      L[NR] = $0
      Q0[NR] = QS
      if (HD != "") {
        T[NR] = ""
        x = $0
        if (HDT) sub(/^\t+/, "", x)
        if (x == HD) HD = ""
        next
      }
      T[NR] = strip($0)
      if (QS == "" && match(T[NR], /<<-?[ \t]*/) && substr(T[NR], RSTART + 2, 1) != "<") {
        HDT = (substr(T[NR], RSTART + 2, 1) == "-")
        x = substr($0, RSTART + RLENGTH)
        if (match(x, /^[\047"]?[A-Za-z_][A-Za-z_0-9]*/)) { HD = substr(x, RSTART, RLENGTH); gsub(/[\047"]/, "", HD) }
      }
    }
    END {
      # The body of a loop fed by a pipe runs in a child. Its indentation is the
      # one of the line its statement starts on (a quoted program may span lines).
      for (j = 1; j <= NR; j++) {
        if (T[j] !~ /\|[ \t]*(while|until|for)[ \t]/ || T[j] ~ /(^|[;&| \t])done([ \t;&|)<]|$)/) continue
        b = j
        while (b > 1 && Q0[b] != "") b--
        for (k = j + 1; k <= NR; k++) {
          if (Q0[k] != "" || T[k] ~ /^[ \t]*$/) continue
          if (indent(L[k]) <= indent(L[b])) break
        }
        if (k <= NR && indent(L[k]) == indent(L[b]) && T[k] ~ /^[ \t]*done([ \t;&|)]|$)/) for (m = j + 1; m < k; m++) child[m] = 1
      }
      for (i = 1; i <= NR; i++) {
        t = T[i]
        if (!match(t, /(^|[;&| \t])done[ \t]*(<[ \t]*<\(|\\$)/)) continue
        p = RSTART + (substr(t, RSTART, 1) ~ /[;&| \t]/ ? 1 : 0)
        if (substr(t, p) ~ /^done[ \t]*\\$/ && T[i + 1] !~ /^[ \t]*<[ \t]*<\(/) continue
        head = substr(t, 1, p - 1)
        # On one line: the loop opens before its done.
        if (match(head, /(^|[;&| \t])(while|until|for)[ \t]/)) { writes(substr(head, RSTART), i); continue }
        start = 0
        for (j = i - 1; j > 0; j--) {
          if (Q0[j] != "" || T[j] ~ /^[ \t]*$/) continue
          if (indent(L[j]) < indent(L[i])) break
          if (indent(L[j]) == indent(L[i])) { if (T[j] ~ /^[ \t]*(while|until|for)([ \t]|$)/) start = j; break }
        }
        if (!start) { printf "%s:%d:cannot find the start of this loop: %s\n", F, i, L[i]; continue }
        for (j = start; j < i; j++) {
          if (j in child) continue
          s = T[j]; k = j
          while (s ~ /\\$/ && k + 1 < i) { k++; s = substr(s, 1, length(s) - 1) " " T[k] }
          writes(s, j)
        }
        writes(head, i)
      }
      for (i = 1; i <= NR; i++) if (i in bad) printf "%s:%d:%s\n", F, i, L[i]
    }' "$path")
  # Kept, and printed once the loop is done: this loop is fed by a process substitution too.
  [ -z "$out" ] || found="$found$out"$'\n'
done < <(for d in "$@"; do find "$d" -type f \( -name '*.sh' -o -name vbw \) -print0; done)
[ -n "$found" ] || exit 0
printf '%s' "$found"
printf 'a builtin write inside a loop fed by a process substitution: write through vbw_out, or pipe the producer into the loop\n' >&2
exit 1
