#!/usr/bin/env bash
# Measure one fix round (R182, maintainers only; never shipped). Builds a fresh
# practice project, then closes its open fixes one of two ways and prints how
# long that took on the wall clock and how much the kernel ran:
#   per-group  every group runs its own vbw fix done, all started at once
#              (what every Dev did until the workflow changed)
#   round      one vbw fix done naming every fix (what the workflow does now)
# usage: tools/measure-fix-round.sh per-group|round GROUPS
# GROUPS is a whole number of 1 or more. The last group is a fix of the test
# command (so test files are measured); the others are fixes of requirements.
# Environment: VBW_MEASURE_DIR (where the project is built; default
# .vbw/runtime/scratch/measure-fix-round in this repository, rebuilt every run),
# VBW_MEASURE_SECONDS (how long each check and test file takes; default 10).
set -euo pipefail

usage='usage: tools/measure-fix-round.sh per-group|round GROUPS  (GROUPS: a whole number of 1 or more)'
case "${1-}" in per-group | round) ;; *) echo "$usage" >&2; exit 2 ;; esac
case "${2-}" in '' | *[!0-9]* | 0*) echo "$usage" >&2; exit 2 ;; esac
[ $# -eq 2 ] || { echo "$usage" >&2; exit 2; }
mode="$1"
groups="$2"

here="$(cd "$(dirname "$0")/.." && pwd)"
vbw="$here/plugin/bin/vbw"
dir="${VBW_MEASURE_DIR:-$here/.vbw/runtime/scratch/measure-fix-round}"
secs="${VBW_MEASURE_SECONDS:-10}"
case "$secs" in '' | *[!0-9]*) echo "VBW_MEASURE_SECONDS must be a whole number" >&2; exit 2 ;; esac
tfiles=4
perreq=2

# The directory is rebuilt every run; only one this tool built (or a new one) is removed.
if [ -e "$dir" ]; then
  [ -f "$dir/.measure-fix-round" ] || { echo "vbw: $dir exists and is not a measure-fix-round project; remove it or set VBW_MEASURE_DIR" >&2; exit 1; }
  rm -rf "$dir"
fi
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
touch "$dir/.measure-fix-round"

# Nothing of the maintainer's machine reaches the practice project.
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
mkdir -p "$proj" "$out"
cd "$proj"
git init -q
printf 'seed\n' > README.md
git add README.md && git commit -q -m "chore: seed"
"$vbw" init > /dev/null

mkdir -p src tests
spec='# Practice\n\n## Requirements\n\n'
g=1
while [ "$g" -le "$groups" ]; do
  spec="$spec- R$g [auto] Feature $g works\n"
  g=$((g + 1))
done
spec="$spec\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n"
printf '%b' "$spec" > .vbw/spec.md
"$vbw" spec sync > /dev/null

printf 'true\n' > tests/all.sh
t=1
while [ "$t" -le "$tfiles" ]; do
  printf 'sleep %s\ngrep -q . src/data.txt\n' "$secs" > "tests/t_$t.sh"
  t=$((t + 1))
done
printf 'data\n' > src/data.txt

phases='' plans='' checks='' cn=0
g=1
while [ "$g" -le "$groups" ]; do
  printf 'feature %s\n' "$g" > "src/f$g.txt"
  k=1
  while [ "$k" -le "$perreq" ]; do
    printf 'sleep %s\ngrep -q . src/f%s.txt\n' "$secs" "$g" > "tests/f${g}_$k.sh"
    cn=$((cn + 1))
    checks="$checks{\"id\":\"C$cn\",\"req\":\"R$g\",\"run\":[\"sh\",\"tests/f${g}_$k.sh\"],\"files\":[\"tests/f${g}_$k.sh\"]},"
    k=$((k + 1))
  done
  phases="$phases{\"id\":\"P$g\",\"title\":\"Feature $g\",\"reqs\":[\"R$g\"],\"tier\":\"standard\"},"
  plans="$plans{\"id\":\"P$g.1\",\"phase\":\"P$g\",\"title\":\"Feature $g\",\"reqs\":[\"R$g\"],\"files\":[\"src/f$g.txt\"]},"
  g=$((g + 1))
done
printf '{"phases":[%s],"plans":[%s],"checks":[%s]}' "${phases%,}" "${plans%,}" "${checks%,}" | "$vbw" apply > /dev/null
git add -A && git commit -q -m "feat: built"

# The plans are done; the groups are open fixes: the first GROUPS-1 of a requirement
# each, the last of the test command. Each group's change is committed.
fixes=''
g=1
while [ "$g" -lt "$groups" ]; do
  fixes="$fixes{\"id\":\"F$g\",\"req\":\"R$g\",\"attempts\":0,\"status\":\"open\",\"note\":\"group $g\"},"
  g=$((g + 1))
done
fixes="$fixes{\"id\":\"F$groups\",\"command\":\"test\",\"attempts\":0,\"status\":\"open\",\"note\":\"group $groups\"}"
jq --argjson f "[$fixes]" '.plans[].status = "done" | .fixes = $f' .vbw/record.json > "$dir/edit.json" && cp "$dir/edit.json" .vbw/record.json
"$vbw" approve > /dev/null
g=1
while [ "$g" -lt "$groups" ]; do
  printf 'fixed\n' >> "src/f$g.txt"
  git add "src/f$g.txt" && git commit -q -m "fix: group $g"
  g=$((g + 1))
done
printf 'fixed\n' >> src/data.txt
git add src/data.txt && git commit -q -m "fix: group $groups"

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

start=$(now)
if [ "$mode" = round ]; then
  ids=''
  g=1
  while [ "$g" -le "$groups" ]; do ids="$ids F$g"; g=$((g + 1)); done
  # shellcheck disable=SC2086 # the ids are words
  "$vbw" fix "done" $ids < /dev/null > "$out/round" 2>&1 || { cat "$out/round" >&2; echo "vbw: the round did not close" >&2; exit 1; }
else
  pids=''
  g=1
  while [ "$g" -le "$groups" ]; do
    "$vbw" fix "done" "F$g" < /dev/null > "$out/g$g" 2>&1 &
    pids="$pids $!"
    g=$((g + 1))
  done
  failed=0
  for p in $pids; do wait "$p" || failed=1; done
  [ "$failed" = 0 ] || { cat "$out"/g* >&2; echo "vbw: a group did not close" >&2; exit 1; }
fi
end=$(now)

# A unit that ran has a line "NAME pass|fail|timeout ..."; one that was reused says "unchanged since".
cat "$out"/* | grep -E '^(C[0-9]+|tests/[^ ]+) (pass|fail|timeout)' > "$out/units" || true
checks_run=$(grep -cE '^C[0-9]+ ' "$out/units" || true)
files_run=$(grep -cE '^tests/' "$out/units" || true)
twice=$(cut -d' ' -f1 "$out/units" | sort | uniq -d | wc -l | tr -d ' ')

printf 'fixture: %s finished requirements with %s checks each, %s test files, %s seconds per check and per test file\n' "$groups" "$perreq" "$tfiles" "$secs"
printf 'mode: %s\n' "$mode"
printf 'groups: %s\n' "$groups"
awk -v a="$start" -v b="$end" 'BEGIN { printf "minutes: %.2f\n", (b - a) / 60 }'
printf 'checks run: %s\n' "$checks_run"
printf 'test files run: %s\n' "$files_run"
printf 'ran more than once: %s\n' "$twice"
