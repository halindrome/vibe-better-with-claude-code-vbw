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
# are not code. A call to a function that writes counts as the write: a first
# pass over the shell files under all DIRs collects the writer functions (a
# function whose body holds a builtin write that runs in the function's own
# shell under the rules above, or, to a fixed point, calls a writer so), and a
# call to a writer in the loop's own shell is refused like a printf: the calling
# line's FILE:LINE:text, then the writer's name and where it writes (FILE:LINE).
# A writer called in a child of its own or with its output into a file passes.
set -euo pipefail
[ $# -ge 1 ] || { printf 'usage: check-loop-writes.sh DIR...\n' >&2; exit 2; }
for d in "$@"; do
  [ -d "$d" ] || { printf 'no directory: %s\n' "$d" >&2; exit 2; }
done
files=()
n=0
while IFS= read -r -d '' path; do
  files+=("$path")
  n=$((n + 1))
done < <(for d in "$@"; do find "$d" -type f \( -name '*.sh' -o -name vbw \) -print0; done)
[ "$n" -gt 0 ] || exit 0
found=$(awk '
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
    # open(s, d): how many parentheses s leaves open (a substitution or a
    # subshell), counting on from d left open before it.
    function open(s, d,    i, c) {
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
    # writes(t, d): the first command in the code text t (d parentheses left
    # open before it) that writes in the shell running t: a builtin write
    # (printf or echo) or a call to a writer function W; "" when there is none.
    function writes(t, d,    rest, pre, seg, w, nx) {
      rest = t
      while (match(rest, /[A-Za-z_][A-Za-z0-9_]*/)) {
        w = substr(rest, RSTART, RLENGTH)
        pre = substr(t, 1, length(t) - length(rest) + RSTART - 1)
        seg = substr(rest, RSTART + RLENGTH)
        rest = seg
        if (w != "printf" && w != "echo" && !(w in W)) continue
        # Followed by an argument or the end of the command (never say=1, say.sh).
        nx = substr(seg, 1, 1)
        if (nx != "" && nx !~ /[ \t;&|)<>]/) continue
        # printf -v VAR sets a variable and writes nothing.
        if (w == "printf" && seg ~ /^[ \t]+-v[ \t]/) continue
        # Its definition, never a call.
        if (seg ~ /^[ \t]*\(\)/) continue
        # Part of a longer word (sprintf, vbw_echo, $say), never the command itself.
        if (pre != "" && substr(pre, length(pre), 1) ~ /[A-Za-z0-9_.\/$-]/) continue
        if (pre ~ /\$\{$/) continue
        sub(/[ \t]+$/, "", pre)
        # Only a command, never an argument (command -v printf).
        if (pre != "" && pre !~ /[;&|({!]$/ && pre !~ /(^|[ \t])(then|do|else|if|while|until|elif)$/) continue
        # In a child: a command or process substitution, a subshell, a later pipeline stage.
        if (open(pre, d) > 0 || (pre ~ /\|$/ && pre !~ /\|\|$/)) continue
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
        return w
      }
      return ""
    }
    # where(w, ln): where the write that w names on line ln happens.
    function where(w, ln) { return (w == "printf" || w == "echo") ? F[ln] ":" FL[ln] : W[w] }
    # joined(j, last): line j with the lines its backslashes continue (up to
    # line last); NX is the last line taken.
    function joined(j, last,    s) {
      s = T[j]; NX = j
      while (s ~ /\\$/ && NX + 1 <= last) { NX++; s = substr(s, 1, length(s) - 1) " " T[NX] }
      return s
    }
    # mark(t, ln): line ln writes in the loop shell when t does.
    function mark(t, ln,    w) {
      w = writes(t, 0)
      if (w != "" && !(ln in bad)) bad[ln] = w
    }
    FNR == 1 { QS = ""; HD = ""; nf++; FN[nf] = FILENAME; S[nf] = NR }
    {
      E[nf] = NR
      F[NR] = FILENAME
      FL[NR] = FNR
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
      nfn = 0
      for (f = 1; f <= nf; f++) {
        s0 = S[f]; e0 = E[f]
        # The body of a loop fed by a pipe runs in a child. Its indentation is the
        # one of the line its statement starts on (a quoted program may span lines).
        for (j = s0; j <= e0; j++) {
          if (T[j] !~ /\|[ \t]*(while|until|for)[ \t]/ || T[j] ~ /(^|[;&| \t])done([ \t;&|)<]|$)/) continue
          b = j
          while (b > s0 && Q0[b] != "") b--
          for (k = j + 1; k <= e0; k++) {
            if (Q0[k] != "" || T[k] ~ /^[ \t]*$/) continue
            if (indent(L[k]) <= indent(L[b])) break
          }
          if (k <= e0 && indent(L[k]) == indent(L[b]) && T[k] ~ /^[ \t]*done([ \t;&|)]|$)/) for (m = j + 1; m < k; m++) child[m] = 1
        }
        # So does the body of a block or loop whose output goes into a pipe or a
        # file (done > FILE, } | CMD): from its opening line, the nearest line
        # above at the same indentation, to its closing one.
        for (k = s0; k <= e0; k++) {
          if (Q0[k] != "" || !match(T[k], /^[ \t]*(done|\})/)) continue
          x = substr(T[k], RSTART + RLENGTH)
          if (x !~ /^[ \t]*\|[^|]/ && x !~ /^[ \t]*(1?>>?|&>>?)[ \t]*[^ \t&>]/) continue
          for (j = k - 1; j >= s0; j--) {
            if (Q0[j] != "" || T[j] ~ /^[ \t]*$/) continue
            if (indent(L[j]) <= indent(L[k])) break
          }
          if (j >= s0 && indent(L[j]) == indent(L[k])) for (m = j + 1; m < k; m++) child[m] = 1
        }
        # The functions: a body on its definition line ({ ...; }), or the lines
        # down to the } at the indentation of the definition.
        for (j = s0; j <= e0; j++) {
          if (Q0[j] != "" || !match(T[j], /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*(\(\))?[ \t]*\{/)) continue
          x = substr(T[j], 1, RLENGTH)
          rest = substr(T[j], RLENGTH + 1)
          if (x !~ /\(\)/ && x !~ /^[ \t]*function[ \t]/) continue
          sub(/^[ \t]*(function[ \t]+)?/, "", x)
          match(x, /^[A-Za-z_][A-Za-z0-9_]*/)
          name = substr(x, 1, RLENGTH)
          dp = 0; one = -1
          for (i = 1; i <= length(rest); i++) {
            c = substr(rest, i, 1)
            if (c == "{") dp++
            else if (c == "}") { if (dp == 0) { one = i; break }; dp-- }
          }
          nfn++; FNAME[nfn] = name; FDEF[nfn] = j
          if (one > 0) {
            FONE[nfn] = substr(rest, 1, one - 1)
            # Its output into a pipe or a file: no write of its own.
            x = substr(rest, one + 1)
            if (x ~ /^[ \t]*\|[^|]/ || x ~ /^[ \t]*(1?>>?|&>>?)[ \t]*[^ \t&>]/) FONE[nfn] = ""
            FEND[nfn] = j
            continue
          }
          FONE[nfn] = ""
          for (k = j + 1; k <= e0; k++) {
            if (Q0[k] != "" || T[k] ~ /^[ \t]*$/) continue
            if (indent(L[k]) <= indent(L[j])) break
          }
          FEND[nfn] = (k <= e0 && indent(L[k]) == indent(L[j]) && T[k] ~ /^[ \t]*\}/) ? k : k - 1
        }
      }
      # The writer functions, to a fixed point: W[name] is where it writes,
      # VIA[name] the writer it calls to write, if any.
      do {
        changed = 0
        for (q = 1; q <= nfn; q++) {
          name = FNAME[q]
          if (name in W) continue
          w = ""; at = 0
          if (FDEF[q] == FEND[q]) { w = writes(FONE[q], 0); at = FDEF[q] }
          else {
            d = 0
            for (j = FDEF[q] + 1; j < FEND[q]; j = NX + 1) {
              s = joined(j, FEND[q] - 1)
              if (!(j in child)) { w = writes(s, d); at = j }
              if (w != "") break
              d = open(s, d)
            }
          }
          if (w == "") continue
          W[name] = where(w, at)
          if (w != "printf" && w != "echo") VIA[name] = w
          changed = 1
        }
      } while (changed)
      for (f = 1; f <= nf; f++) {
        s0 = S[f]; e0 = E[f]
        for (i = s0; i <= e0; i++) {
          t = T[i]
          if (!match(t, /(^|[;&| \t])done[ \t]*(<[ \t]*<\(|\\$)/)) continue
          p = RSTART + (substr(t, RSTART, 1) ~ /[;&| \t]/ ? 1 : 0)
          if (substr(t, p) ~ /^done[ \t]*\\$/ && T[i + 1] !~ /^[ \t]*<[ \t]*<\(/) continue
          head = substr(t, 1, p - 1)
          # On one line: the loop opens before its done.
          if (match(head, /(^|[;&| \t])(while|until|for)[ \t]/)) { mark(substr(head, RSTART), i); continue }
          start = 0
          for (j = i - 1; j >= s0; j--) {
            if (Q0[j] != "" || T[j] ~ /^[ \t]*$/) continue
            if (indent(L[j]) < indent(L[i])) break
            if (indent(L[j]) == indent(L[i])) { if (T[j] ~ /^[ \t]*(while|until|for)([ \t]|$)/) start = j; break }
          }
          if (!start) { printf "%s:%d:cannot find the start of this loop: %s\n", F[i], FL[i], L[i]; continue }
          for (j = start; j < i; j++) {
            if (j in child) continue
            mark(joined(j, i - 1), j)
          }
          mark(head, i)
        }
        for (i = s0; i <= e0; i++) {
          if (!(i in bad)) continue
          printf "%s:%d:%s\n", F[i], FL[i], L[i]
          w = bad[i]
          if (w == "printf" || w == "echo") continue
          via = ""; c = w
          for (k = 0; (c in VIA) && k < 50; k++) { c = VIA[c]; via = via ", through " c }
          printf "  calls %s, a function that writes at %s%s\n", w, W[w], via
        }
      }
    }' "${files[@]}")
[ -n "$found" ] || exit 0
printf '%s\n' "$found"
printf 'a builtin write, or a call to a function that writes so, inside a loop fed by a process substitution: write through vbw_out, or pipe the producer into the loop\n' >&2
exit 1
