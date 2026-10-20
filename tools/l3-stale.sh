#!/usr/bin/env bash
# Find a real-session (L3) result older than the code it covers.
#   bash tools/l3-stale.sh [--repo DIR]
# Reads DIR/tools/l3-suite.sh: the ALL list, and for each scenario its
# '# covers: <git pathspecs>' comment line (the nearest one above
# scenario_NAME() with only comment lines between). A scenario is stale when
# DIR/tools/l3-results/NAME.json is missing, or its 'at' is before the newest
# commit (committer time) touching the pathspecs.
# Output: one 'stale:' line per stale scenario in ALL's order, then the command
# to run them; exit 1. Nothing stale: one line, exit 0. A scenario without a
# covers line, or a shallow clone: 'cannot judge: <why>', exit 2.
# Needs no Claude Code, network or money: git and jq only.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
case "$#:${1-}" in
  0:) ;;
  2:--repo) repo="$2" ;;
  *) echo "usage: tools/l3-stale.sh [--repo DIR]" >&2; exit 2 ;;
esac

suite="$repo/tools/l3-suite.sh"
cannot() { echo "cannot judge: $1"; exit 2; }

[ -f "$suite" ] || cannot "$suite does not exist"
[ "$(git -C "$repo" rev-parse --is-shallow-repository 2>/dev/null || echo true)" = false ] \
  || cannot "the clone is shallow or not a git repository, so commit times are incomplete"

all=$(sed -n 's/^ALL="\(.*\)"$/\1/p' "$suite" | head -n 1)
[ -n "$all" ] || cannot "no ALL list in tools/l3-suite.sh"

# covers_of NAME: the pathspecs of NAME's covers line, space separated.
covers_of() {
  awk -v name="$1" '
    /^# covers:/ { c = $0; sub(/^# covers:[ \t]*/, "", c) }
    /^scenario_[A-Za-z0-9_-]+\(\)/ { n = $0; sub(/\(\).*/, "", n); sub(/^scenario_/, "", n); if (n == name) { print c; exit } }
    !/^#/ { c = "" }' "$suite"
}

set -f # pathspecs are globs for git, not for this shell
stale_names=""
stale_lines=""
count=0
for name in $all; do
  count=$((count + 1))
  covers=$(covers_of "$name")
  [ -n "$covers" ] || cannot "scenario $name has no '# covers:' line above scenario_$name()"
  specs=()
  for p in $covers; do specs+=("$p"); done
  info=$(git -C "$repo" log -1 --format='%h %cI %ct' -- ${specs[@]+"${specs[@]}"})
  [ -n "$info" ] || continue # no commit touches the covered files: nothing to be older than
  hash=${info%% *}
  rest=${info#* }
  cdate=${rest%% *}
  ctime=${rest##* }
  file="$repo/tools/l3-results/$name.json"
  if [ ! -f "$file" ]; then
    at_text="no result"
    is_stale=1
  else
    at=$(jq -r '.at // empty' "$file" 2>/dev/null) || at=
    atime=$(jq -r '.at | fromdateiso8601' "$file" 2>/dev/null) || atime=
    [ -n "$atime" ] || cannot "tools/l3-results/$name.json has no readable 'at' time"
    at_text=${at%%T*}
    is_stale=0
    [ "$ctime" -gt "$atime" ] && is_stale=1
  fi
  if [ "$is_stale" = 1 ]; then
    stale_names="${stale_names:+$stale_names }$name"
    stale_lines="${stale_lines}stale: $name  result $at_text  newest commit $hash ${cdate%%T*}"$'\n'
  fi
done

if [ -z "$stale_names" ]; then
  echo "no stale real-session result ($count scenarios)"
  exit 0
fi
printf '%s' "$stale_lines"
echo "run: bash tools/l3-suite.sh $stale_names"
exit 1
