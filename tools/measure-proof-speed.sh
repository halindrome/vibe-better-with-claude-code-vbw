#!/usr/bin/env bash
# Measure the proof's speed on a large stand-in project (R202, maintainers only;
# never shipped). The stand-in is generated: a two-level folder tree of small
# text files, half approved checks and half test files under an approved
# single-file form, where every fourth unit writes hundreds of files into a
# git-ignored build cache (.buildcache/, which the clean copy carries) and the
# unit after it reads them back. Nothing of any real user project is in it.
#
# usage: tools/measure-proof-speed.sh [--files N] [--folders N] [--units N] [--generate DIR]
#   --files N      source files of the stand-in (default 5000)
#   --folders N    folders holding them (default 500)
#   --units N      units: half checks, half test files (default 200)
#   --two          instead of the usual measurement: a second copy of the stand-in
#                  (its own folder, same home and slot store), both proved at once
#                  while the slot store is sampled; prints the machine limit, the
#                  most slots held, the units' average while units ran and the
#                  wall seconds
#   --generate DIR build the stand-in at DIR in the caller's environment, print
#                  its 'fixture:' line and stop
# Without --generate it builds the stand-in in an isolated HOME and
# CLAUDE_CONFIG_DIR under VBW_MEASURE_DIR (default
# .vbw/runtime/scratch/measure-proof-speed in this repository, rebuilt every
# run), then runs vbw prove, appends one line to one source file some units
# read, closes an open fix of R1 with vbw fix done, and runs vbw next --json,
# printing one 'name: value' line per figure. During the proof (both proofs
# with --two) the slot store is sampled five times a second: the slots its units
# hold (VBW's own vbw:* bookkeeping entries left out), averaged over the whole
# proof and over the samples from the first that shows a unit to the last.
set -euo pipefail

usage='usage: tools/measure-proof-speed.sh [--files N] [--folders N] [--units N] [--two] [--generate DIR]'
files=5000 folders=500 units=200 gen='' two=0
while [ $# -gt 0 ]; do
  case "$1" in
    --files | --folders | --units)
      [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
      case "$2" in '' | *[!0-9]* | 0*) echo "$1 takes a whole number of 1 or more" >&2; exit 2 ;; esac
      case "$1" in --files) files="$2" ;; --folders) folders="$2" ;; *) units="$2" ;; esac
      shift 2 ;;
    --two)
      two=1
      shift ;;
    --generate)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "$usage" >&2; exit 2; }
      gen="$2"
      shift 2 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
[ "$folders" -le "$files" ] || { echo "--folders cannot exceed --files" >&2; exit 2; }
[ -z "$gen" ] || [ "$two" -eq 0 ] || { echo "--two and --generate cannot be combined" >&2; exit 2; }
[ "$units" -ge 2 ] || { echo "--units takes 2 or more" >&2; exit 2; }

here="$(cd "$(dirname "$0")/.." && pwd)"
vbw="$here/plugin/bin/vbw"

# source_path I: the source file number I (0-based): files spread over the folders,
# two levels deep (src/gNN/dNNNN/fNNNN.txt).
source_path() {
  local d=$(($1 % folders)) f=$(($1 / folders))
  printf 'src/g%03d/d%04d/f%04d.txt' $((d % 25)) "$d" "$f"
}

# generate DIR: build the stand-in in the current environment.
generate() {
  local dir="$1" i k n
  mkdir -p "$dir"
  dir="$(cd "$dir" && pwd)"
  cd "$dir"
  git init -q
  printf 'seed\n' > README.md
  git add README.md && git commit -q -m "chore: seed"
  "$vbw" init > /dev/null
  printf '.buildcache/\n' >> .gitignore

  # The source tree.
  i=0
  while [ "$i" -lt "$files" ]; do
    n="$(source_path "$i")"
    mkdir -p "$(dirname "$n")"
    printf 'source file %s\nvalue %s\n' "$i" $((i * 7 % 101)) > "$n"
    i=$((i + 1))
  done

  # The units: odd numbers are approved checks (tests/c_N.sh), even numbers test
  # files (tests/t_N.sh). Each reads five source files; every fourth unit writes
  # 300 files into .buildcache/uN and the unit after it reads them back.
  mkdir -p tests
  local unit_script
  i=1
  while [ "$i" -le "$units" ]; do
    if [ $((i % 2)) -eq 1 ]; then unit_script="tests/c_$i.sh"; else unit_script="tests/t_$i.sh"; fi
    {
      k=0
      while [ "$k" -lt 5 ]; do
        printf 'cat %s > /dev/null\n' "$(source_path $(((i * 37 + k * 211) % files)))"
        k=$((k + 1))
      done
      if [ $((i % 4)) -eq 0 ]; then
        # shellcheck disable=SC2016 # the unit script expands its own variables

        # shellcheck disable=SC2016 # the unit script expands its own variables
        printf 'mkdir -p .buildcache/u%s\nn=0\nwhile [ "$n" -lt 300 ]; do\n  printf "object %%s\\n" "$n" > ".buildcache/u%s/o$n.o"\n  n=$((n + 1))\ndone\n' "$i" "$i"
      elif [ $((i % 4)) -eq 1 ] && [ "$i" -gt 1 ]; then
        printf 'if [ -d .buildcache/u%s ]; then cat .buildcache/u%s/* > /dev/null; fi\n' $((i - 1)) $((i - 1))
      fi
      printf 'true\n'
    } > "$unit_script"
    i=$((i + 1))
  done
  printf 'true\n' > tests/all.sh

  local spec
  spec='# Stand-in\n\n## Requirements\n\n- R1 [auto] Every unit of the stand-in passes (its contract is APPROVED before the first proof)\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n'
  printf '%b' "$spec" > .vbw/spec.md
  "$vbw" spec sync > /dev/null

  local checks='' cn=0
  i=1
  while [ "$i" -le "$units" ]; do
    if [ $((i % 2)) -eq 1 ]; then
      cn=$((cn + 1))
      checks="$checks{\"id\":\"C$cn\",\"req\":\"R1\",\"run\":[\"sh\",\"tests/c_$i.sh\"],\"files\":[\"tests/c_$i.sh\"]},"
    fi
    i=$((i + 1))
  done
  printf '{"phases":[{"id":"P1","title":"Stand-in","reqs":["R1"],"tier":"standard"}],"plans":[{"id":"P1.1","phase":"P1","title":"Stand-in","reqs":["R1"],"files":["%s"]}],"checks":[%s]}' \
    "$(source_path 0)" "${checks%,}" | "$vbw" apply > /dev/null
  jq '.plans[].status = "done"' .vbw/record.json > .vbw/runtime/edit.json && cp .vbw/runtime/edit.json .vbw/record.json
  "$vbw" approve > /dev/null
  git add -A && git commit -q -m "feat: the stand-in"
  printf 'fixture: stand-in (%s files, %s folders, %s units)\n' "$files" "$folders" "$units"
}

if [ -n "$gen" ]; then
  generate "$gen"
  exit 0
fi

# ---- the measurement ---------------------------------------------------------
dir="${VBW_MEASURE_DIR:-$here/.vbw/runtime/scratch/measure-proof-speed}"

# The directory is rebuilt every run; only one this tool built (or a new one) is removed.
if [ -e "$dir" ]; then
  [ -f "$dir/.measure-proof-speed" ] || { echo "vbw: $dir exists and is not a measure-proof-speed project; remove it or set VBW_MEASURE_DIR" >&2; exit 1; }
  rm -rf "$dir"
fi
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
touch "$dir/.measure-proof-speed"

# Nothing of the maintainer's machine reaches the stand-in.
unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE CLAUDECODE CLAUDE_CODE_ENTRYPOINT
export HOME="$dir/home" CLAUDE_CONFIG_DIR="$dir/home/.claude" CLAUDE_PLUGIN_DATA="$dir/plugin-data"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$dir/gitconfig" LC_ALL=C
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$CLAUDE_PLUGIN_DATA"
git config --global user.email "measure@example.com"
git config --global user.name "Measure"
git config --global init.defaultBranch main
git config --global gc.auto 0

proj="$dir/project"
out="$dir/out"
mkdir -p "$out"
fixture=$(generate "$proj")
cd "$proj"
limit=$(bash -c 'source "$1/plugin/lib/core.sh"; vbw_machine_limit' _ "$here")
slots="$CLAUDE_CONFIG_DIR/vbw/slots.json"

# sample_held FILE STOP [PROJECT...]: five times a second until STOP exists, one
# line per sample in FILE: the slots held in the store (VBW's own vbw:* entries
# included), those held by units (left out), and the gate registrations of the
# PROJECTs (a cross-check of the store).
sample_held() {
  local file="$1" stop="$2" h g f p
  shift 2
  while [ ! -e "$stop" ]; do
    h='0 0'
    [ ! -f "$slots" ] || h=$(jq -r '"\(.held | length) \([.held[] | select(.id | startswith("vbw:") | not)] | length)"' "$slots" 2> /dev/null) || h='0 0'
    g=0
    for p in "$@"; do
      for f in "$p"/.vbw/runtime/gate/reg.*; do
        [ ! -e "$f" ] || g=$((g + 1))
      done
    done
    printf '%s %s\n' "${h:-0 0}" "$g" >> "$file"
    sleep 0.2
  done
}

# held_figures FILE: "MAX GATES AVERAGE WHILE" of the samples in FILE: the most
# slots held and the most gate registrations at any sample, the units' average
# over every sample, and over the samples from the first that shows a unit to the last.
held_figures() {
  awk '{ n++; if ($1 > max) max = $1; if ($3 > gmax) gmax = $3; u[n] = $2; s += $2; if ($2 > 0) { if (!first) first = n; last = n } }
    END { w = 0; if (first) { for (i = first; i <= last; i++) w += u[i]; w /= last - first + 1 }
          printf "%d %d %.2f %.2f\n", max, gmax, (n ? s / n : 0), w }' "$1"
}

if [ "$two" -eq 1 ]; then
  now_s() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
  proj2="$dir/project2"
  generate "$proj2" > /dev/null
  sample_held "$out/held" "$out/stop" "$proj" "$proj2" &
  sampler=$!
  s=$(now_s)
  rc1=0 rc2=0
  (cd "$proj" && "$vbw" prove < /dev/null > "$out/prove1" 2>&1) & p1=$!
  (cd "$proj2" && "$vbw" prove < /dev/null > "$out/prove2" 2>&1) & p2=$!
  wait "$p1" || rc1=$?
  wait "$p2" || rc2=$?
  e=$(now_s)
  touch "$out/stop"
  wait "$sampler"
  if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
    cat "$out/prove1" "$out/prove2" >&2
    echo "vbw: a proof did not pass" >&2
    exit 1
  fi
  read -r held gates _ during < <(held_figures "$out/held") || { held=0; gates=0; during=0; }
  printf '%s\n' "$fixture"
  printf 'machine limit: %s\n' "$limit"
  printf 'two proofs max held: %s\n' "$held"
  printf 'two proofs average held while units run: %s\n' "$during"
  printf 'two proofs gate registrations max: %s\n' "$gates"
  printf 'two proofs wall seconds: %s\n' "$(awk -v a="$s" -v b="$e" 'BEGIN { printf "%.2f", b - a }')"
  exit 0
fi

# A jq wrapper, first on the PATH of the measured commands: it runs the real jq
# and appends the CPU time of its children (the shell's times builtin: the user
# and system seconds of the processes it waited for) to its own log.
realjq=$(command -v jq)
wrap="$dir/wrap"
mkdir -p "$wrap" "$out/jq"
cat > "$wrap/jq" << WRAP
#!/bin/sh
"$realjq" "\$@"
rc=\$?
times >> "$out/jq/log"
exit \$rc
WRAP
chmod +x "$wrap/jq"

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

# The sampler keeps the largest written.json seen, ten times a second (the lists live only
# while the proof runs, about a second on a fast machine), until told to stop.
(
  max=0
  while [ ! -e "$out/stop" ]; do
    for f in "$proj"/.vbw/runtime/proof.*/reads/written.json; do
      [ -f "$f" ] || continue
      s=$(wc -c < "$f" | tr -d ' ')
      [ "$s" -le "$max" ] || { max="$s"; printf '%s\n' "$max" > "$out/maxwritten"; }
    done
    sleep 0.1
  done
) &
sampler=$!

# timed NAME COMMAND...: run COMMAND (jq wrapped), keep its output in out/NAME, set WALL.
timed() {
  local name="$1" s e rc=0
  shift
  s=$(now)
  PATH="$wrap:$PATH" "$@" < /dev/null > "$out/$name" 2>&1 || rc=$?
  e=$(now)
  WALL=$(awk -v a="$s" -v b="$e" 'BEGIN { printf "%.2f", b - a }')
  return "$rc"
}

sample_held "$out/held" "$out/proved" "$proj" &
held_sampler=$!
prove_rc=0
timed prove "$vbw" prove || prove_rc=$?
touch "$out/proved"
wait "$held_sampler"
[ "$prove_rc" -eq 0 ] || { cat "$out/prove" >&2; echo "vbw: the proof did not pass" >&2; touch "$out/stop"; wait "$sampler"; exit 1; }
prove_wall="$WALL"
read -r _ _ held_avg held_during < <(held_figures "$out/held") || { held_avg=0; held_during=0; }
own() { jq -r --arg k "$1" '.evidence.own[$k] // 0' "$proj/.vbw/record.json"; }
p_plan=$(own planning) p_copies=$(own copies) p_track=$(own tracking) p_save=$(own saving) p_record=$(own record)
p_own=$(awk -v a="$p_plan" -v b="$p_copies" -v c="$p_track" -v d="$p_save" -v e="$p_record" 'BEGIN { printf "%.2f", a + b + c + d + e }')

# One small change to a source file some units read, and an open fix of R1.
changed="$(source_path $((37 % files)))"
printf 'one more line\n' >> "$changed"
jq '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "one source file changed"}]' .vbw/record.json > .vbw/runtime/edit.json \
  && cp .vbw/runtime/edit.json .vbw/record.json
git add "$changed" .vbw/record.json && git commit -q -m "fix: one source file"

# Expected reuse: the units whose recorded read lists do not contain the changed file.
# A fix of R1 judges R1's checks, so those are the units counted (not the test files or commands).
common=$(git rev-parse --path-format=absolute --git-common-dir)
expected=$(jq --arg f "$changed" '[.runs | to_entries[] | select(.key | startswith("check:")) | .value | select(.reads != null and ((.reads | index($f)) == null))] | length' "$common/vbw/runs.json")

timed fix "$vbw" fix "done" F1 || { cat "$out/fix" >&2; echo "vbw: the fix round did not close" >&2; touch "$out/stop"; wait "$sampler"; exit 1; }
fix_wall="$WALL"
reused=$(sed -n 's/^.*: [0-9]* ran, \([0-9]*\) reused$/\1/p' "$out/fix" | awk '{ n += $1 } END { print n + 0 }')

timed next "$vbw" next --json || { cat "$out/next" >&2; echo "vbw: vbw next failed" >&2; touch "$out/stop"; wait "$sampler"; exit 1; }
next_wall="$WALL"

touch "$out/stop"
wait "$sampler"

# jq: one pair of lines per process, the second holding its children's CPU ("0m0.010s 0m0.004s").
read -r jqcpu jqn < <(awk 'NR % 2 == 0 { for (i = 1; i <= NF; i++) { split($i, a, "m"); sub(/s$/, "", a[2]); t += a[1] * 60 + a[2] } n++ } END { printf "%.2f %d\n", t, n }' "$out/jq/log" 2> /dev/null || echo "0 0")
written=0
[ ! -f "$out/maxwritten" ] || written=$(cat "$out/maxwritten")
store=$(wc -c < "$common/vbw/runs.json" | tr -d ' ')

# lines TEXTFILE: the two report lines of a command.
lines() { grep -E "^(VBW's own work: |ran again: )" "$1"; }
fix_own=$(sed -n "s/^VBW's own work: \([0-9.]*\) of .*$/\1/p" "$out/fix" | head -n 1)

printf '%s\n' "$fixture"
printf 'files: %s\nfolders: %s\nunits: %s\n' "$(git ls-files | wc -l | tr -d ' ')" "$(git ls-files | sed -n 's|/[^/]*$||p' | sort -u | wc -l | tr -d ' ')" "$units"
lines "$out/prove" | sed 's/^/prove: /'
printf 'prove wall seconds: %s\nprove own seconds: %s\nprove planning seconds: %s\nprove copies seconds: %s\nprove tracking seconds: %s\nprove saving seconds: %s\nprove record seconds: %s\n' \
  "$prove_wall" "$p_own" "$p_plan" "$p_copies" "$p_track" "$p_save" "$p_record"
printf 'machine limit: %s\nprove slots held average: %s\nprove slots held while units run: %s\n' "$limit" "$held_avg" "$held_during"
lines "$out/fix" | sed 's/^/fix done: /'
printf 'fix done wall seconds: %s\nfix done own minutes: %s\n' "$fix_wall" "${fix_own:-0}"
printf 'reused: %s\nreused expected: %s\njq cpu seconds: %s\njq processes: %s\nstore bytes: %s\nwritten lists bytes: %s\nnext seconds: %s\n' \
  "$reused" "$expected" "$jqcpu" "$jqn" "$store" "$written" "$next_wall"
