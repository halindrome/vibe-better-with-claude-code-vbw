#!/usr/bin/env bash
# check-private-words.sh [--list FILE] tracked | paths PATH...: the maintainer's
# privacy guard. Nothing a user can read in this repository may name a private
# project of the owner. The words (one word or phrase per line, # starts a
# comment, matched case-insensitively as plain text) live in a list that is never
# committed: a_non_prod_docs/private-words.txt of the main checkout, found through
# the git common directory so every worktree reads the same one. --list FILE
# reads another list (the tests use it).
#   tracked       the tracked files that contain a word (all of them, .vbw/ too:
#                 the plan of record is as public as the code)
#   paths PATH... the files under PATH... that contain a word
# Prints the files found, one per line (never the words). Exit 0: none found;
# 1: found; 2: bad usage or an error; 3: there is no list here (CI and
# contributors), so nothing was checked, and the reason is on stderr.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
list=''
if [ "${1-}" = --list ]; then
  [ $# -ge 2 ] || { printf 'usage: check-private-words.sh [--list FILE] tracked | paths PATH...\n' >&2; exit 2; }
  list="$2"
  shift 2
fi
mode="${1-}"
[ $# -eq 0 ] || shift
case "$mode" in
  tracked) [ $# -eq 0 ] || mode='' ;;
  paths) [ $# -ge 1 ] || mode='' ;;
  *) mode='' ;;
esac
[ -n "$mode" ] || { printf 'usage: check-private-words.sh [--list FILE] tracked | paths PATH...\n' >&2; exit 2; }

if [ -z "$list" ]; then
  # The common directory is relative to $here in the main checkout and absolute in a worktree.
  gitdir=$(cd "$here" && git rev-parse --git-common-dir 2> /dev/null) || gitdir=''
  if [ -n "$gitdir" ]; then
    common=$(cd "$here" && cd "$gitdir" && pwd)
    list="$(dirname "$common")/a_non_prod_docs/private-words.txt"
  fi
fi
if [ -z "$list" ] || [ ! -f "$list" ]; then
  printf 'no private-words list (%s): nothing checked\n' "${list:-no git checkout}" >&2
  exit 3
fi

words=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  case "$line" in '' | '#'*) continue ;; esac
  words+=(-e "$line")
done < "$list"
if [ ${#words[@]} -eq 0 ]; then
  printf 'the private-words list (%s) has no words: nothing checked\n' "$list" >&2
  exit 3
fi

found=0
if [ "$mode" = tracked ]; then
  cd "$here/.."
  git grep -z -l -i -F ${words[@]+"${words[@]}"} | tr '\0' '\n' || found=$?
else
  grep -rli -F ${words[@]+"${words[@]}"} --exclude-dir=.git -- "$@" || found=$?
fi
# git grep and grep end in 1 when nothing matched, and in 2 or more on an error.
case "$found" in
  0) exit 1 ;;
  1) exit 0 ;;
  *) exit 2 ;;
esac
