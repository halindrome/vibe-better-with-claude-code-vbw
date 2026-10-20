#!/usr/bin/env bash
# Why a proof runs everything (docs/proof.md, R168). When VBW cannot tell what
# a change affects, every check and test file runs and each cause is named in
# plain words. A cause is one line of text; no cause means the reuse rule of
# proofreuse.sh decides alone, unit by unit. A content change to a file no
# recorded run read is no cause: it affects nothing that was run. A changed
# approved command, single-file form or list of test files is no cause either:
# each unit's fingerprint carries its own definition, so only what runs through
# the change runs again.

# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"
# shellcheck source=reads.sh
. "$VBW_LIB/reads.sh"

# proofcauses_known RECORD HEAD: the paths that are a run of their own: the
# test files of the approved form and the files the checks serve. A new one
# is not unknown, it is run.
proofcauses_known() {
  local specs=() a
  while IFS= read -r -d '' a; do specs+=("$a"); done < <(printf '%s' "$1" | jq -j '(.test_files.files // [])[] + "\u0000"')
  {
    printf '%s' "$1" | jq -r '(.checks // [])[] | (.files // [])[]'
    [ ${#specs[@]} -eq 0 ] || git -C "$VBW_ROOT" ls-files -z -- ${specs[@]+"${specs[@]}"} | tr '\0' '\n'
  } | jq -R -s -c 'split("\n") | map(select(length > 0))'
}

# proofcauses_files RECORD HEAD STORE: the causes found in the files: an added
# or deleted file that every recorded run with a known tree predates (no run
# saw it), that no run read, that is no test or check file of its own, and
# whose folder no run listed. A change some recorded run already ran with is
# not unseen: the proof that ran it judged it. A file whose own folder appeared
# or vanished with it is seen through the nearest folder above that a run
# listed: that listing gained or lost an entry, and the reuse rule re-runs the
# run that listed it; the file was never reachable any other way.
proofcauses_files() {
  local known head
  [ -n "$2" ] || return 0
  head=$(git -C "$VBW_ROOT" ls-tree -r -z --name-only "$2" 2> /dev/null | jq -R -s -c 'split("\u0000") | map(select(length > 0))')
  [ -n "$head" ] || head='[]'
  # One git diff-tree per distinct recorded tree, shared with the reuse planning (proofreuse_diffs).
  # shellcheck disable=SC2034 # read by proofreuse_diffs
  PROOFREUSE_STORE=$3
  proofreuse_diffs "$2"
  known=$(proofcauses_known "$1" "$2")
  jq -nr --slurpfile df <(printf '%s' "$PROOFREUSE_DIFFS") --slurpfile s <(printf '%s' "$3") --slurpfile known <(printf '%s' "$known") \
    --slurpfile head <(printf '%s' "$head") '
    def parent: if test("/") then sub("/[^/]*$"; "") else "." end;
    # The folders above a path, nearest first, the root (".") last.
    def above: parent as $p | if $p == "." then ["."] else [$p] + ($p | above) end;
    # A recorded run with a known tree: an unknown tree prints null and must not veto; a known tree with no change gives [] and does.
    ([$s[0].runs | to_entries[] | select(.value | type == "object" and (.tree | type) == "string")
      | select($df[0][.value.tree] != null) | .value as $v | {key: .key, reads: $v.reads, dirs: ($v.dirs // []), changes: $df[0][$v.tree]}]) as $e
    | ($e | map(select(.reads | type == "array"))) as $r
    | ($known[0] + [$s[0].runs | keys[] | select(startswith("file:")) | ltrimstr("file:")]) as $own
    | ([$r[].reads[]] | unique) as $read
    | ([$r[].dirs[] | if type == "object" then .path else . end] | unique) as $dirs
    # Unseen: an added or deleted file that every recorded run with a known tree predates.
    | (if ($e | length) == 0 then [] else
         ($e | map([.changes[] | select(.s == "A" or .s == "D") | "\(.s)\u001f\(.p)"] | unique))
         | reduce .[1:][] as $c (.[0]; map(select(. as $x | $c | index($x))))
         | map(split("\u001f") | {s: .[0], p: .[1]}) end) as $unseen
    | ($unseen | map(select(.s == "A") | .p)) as $added
    # Seen through a listing: the nearest listed folder above the file gained the entry that
    # holds the file (every file under it is new) or lost it (nothing is left under it).
    | def through($p; $s):
        ([$p | above[] | select(. as $d | $dirs | index($d))] | .[0]) as $l
        | $l != null
          and (($p | if $l == "." then . else ltrimstr($l + "/") end | split("/")[0]) as $e
               | (if $l == "." then $e else $l + "/" + $e end) as $f
               | [$head[0][] | select(startswith($f + "/"))] as $inside
               | if $s == "A" then ($inside | length) > 0 and all($inside[]; . as $x | $added | index($x))
                 else ($inside | length) == 0 end);
    $unseen
    | map(select(.p as $p | .s as $s | ($read | index($p) | not) and ($own | index($p) | not)
          and (($p | parent) as $d | $dirs | index($d) | not) and (through($p; $s) | not))
         | "\(.p) was \(if .s == "A" then "added" else "deleted" end), and no recorded run read it or listed its folder")
    | sort | .[]'
}

# proofcauses_find RECORD FULL HEAD [KIND]: every cause for this proof, one per
# line, in a fixed order; nothing when the reuse rule may decide alone. FULL is
# 1 for vbw prove --full. HEAD is the tree of the committed code. KIND is
# "prove" (the default) or "fix": a second vbw prove with nothing committed
# since a passing proof is a deliberate re-run and a cause; vbw fix done after
# that proof is not, a passing proof of the same code is exactly what it needs.
proofcauses_find() {
  local store probe
  store=$(proofreuse_store_read)
  [ "$2" != 1 ] || printf 'vbw prove --full\n'
  [ ! -e "$(proofreuse_marker)" ] || printf 'the last proof was cut short\n'
  printf '%s' "$store" | jq -e '(.runs | length) > 0' > /dev/null || printf 'this clone has no earlier recorded run\n'
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || true
  probe=$(reads_probe "$VBW_RUNTIME" 2>&1) || printf '%s\n' "$probe"
  if [ "${4:-prove}" != fix ] && proofreuse_proved "$1" "$3"; then
    printf 'nothing was committed since the last passing proof\n'
  fi
  proofcauses_files "$1" "$3" "$store"
}
