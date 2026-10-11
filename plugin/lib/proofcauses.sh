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

# proofcauses_changes TREE HEAD: the files that differ between two trees, as
# [{s: status letter, p: path}]; nothing when the tree is unknown.
proofcauses_changes() {
  git -C "$VBW_ROOT" diff-tree -z -r --no-renames --name-status "$1" "$2" 2> /dev/null | tr '\0' '\n' \
    | jq -R -s -c '[split("\n")[] | select(length > 0)] as $l | [range(0; $l | length; 2) | {s: $l[.][0:1], p: $l[. + 1]}]'
}

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
# not unseen: the proof that ran it judged it.
proofcauses_files() {
  local key tree entries='[]' ch known
  [ -n "$2" ] || return 0
  while IFS=$'\t' read -r key tree; do
    ch=$(proofcauses_changes "$tree" "$2")
    # An unknown tree prints nothing and must not veto; a known tree with no change prints [] and does.
    [ -n "$ch" ] || continue
    entries=$(printf '%s' "$entries" | jq -c --slurpfile s <(printf '%s' "$3") --slurpfile c <(printf '%s' "$ch") --arg k "$key" \
      '. + [$s[0].runs[$k] | {key: $k, reads, dirs: (.dirs // []), changes: $c[0]}]')
  done < <(printf '%s' "$3" | jq -r '.runs | to_entries[] | select(.value | type == "object" and (.tree | type) == "string") | [.key, .value.tree] | @tsv')
  known=$(proofcauses_known "$1" "$2")
  jq -nr --slurpfile e <(printf '%s' "$entries") --slurpfile s <(printf '%s' "$3") --slurpfile known <(printf '%s' "$known") '
    $e[0] as $e | ($e | map(select(.reads | type == "array"))) as $r
    | ($known[0] + [$s[0].runs | keys[] | select(startswith("file:")) | ltrimstr("file:")]) as $own
    | ([$r[].reads[]] | unique) as $read
    | ([$r[].dirs[] | if type == "object" then .path else . end] | unique) as $dirs
    # Unseen: an added or deleted file that every recorded run with a known tree predates.
    | (if ($e | length) == 0 then [] else
         ($e | map([.changes[] | select(.s == "A" or .s == "D") | "\(.s)\u001f\(.p)"] | unique))
         | reduce .[1:][] as $c (.[0]; map(select(. as $x | $c | index($x))))
         | map(split("\u001f") | {s: .[0], p: .[1]}) end) as $unseen
    | $unseen
    | map(select(.p as $p | ($read | index($p) | not) and ($own | index($p) | not)
          and (($p | if test("/") then sub("/[^/]*$"; "") else "." end) as $d | $dirs | index($d) | not))
         | "\(.p) was \(if .s == "A" then "added" else "deleted" end), and no recorded run read it or listed its folder")
    | sort | .[]'
}

# proofcauses_find RECORD FULL HEAD: every cause for this proof, one per line,
# in a fixed order; nothing when the reuse rule may decide alone. FULL is 1 for
# vbw prove --full. HEAD is the tree of the committed code.
proofcauses_find() {
  local store probe
  store=$(proofreuse_store_read)
  [ "$2" != 1 ] || printf 'vbw prove --full\n'
  [ ! -e "$(proofreuse_marker)" ] || printf 'the last proof was cut short\n'
  printf '%s' "$store" | jq -e '(.runs | length) > 0' > /dev/null || printf 'this clone has no earlier recorded run\n'
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || true
  probe=$(reads_probe "$VBW_RUNTIME" 2>&1) || printf '%s\n' "$probe"
  if [ "$(git -C "$VBW_ROOT" log -1 --format=%s 2> /dev/null)" = 'chore(vbw): proof passed' ] \
    && [ -z "$(git -C "$VBW_ROOT" status --porcelain -z -- .vbw 2> /dev/null | tr -d '\000')" ] \
    && [ "$(vbw_code_tree)" = "$3" ]; then
    printf 'nothing was committed since the last passing proof\n'
  fi
  proofcauses_files "$1" "$3" "$store"
}
