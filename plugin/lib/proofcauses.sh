#!/usr/bin/env bash
# Why a proof runs everything (docs/proof.md, R168). When VBW cannot tell what
# a change affects, every check and test file runs and each cause is named in
# plain words. A cause is one line of text; no cause means the reuse rule of
# proofreuse.sh decides alone. A content change to a file no recorded run read
# is no cause: it affects nothing that was run.

# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"
# shellcheck source=reads.sh
. "$VBW_LIB/reads.sh"

# proofcauses_form RECORD: the approved commands and the test file form as one
# JSON object {commands: {name: fingerprint}, single, list}, kept in the store
# with the runs so the next proof can say which of them changed.
proofcauses_form() {
  local name cmds='{}'
  while IFS= read -r -d '' name; do
    cmds=$(printf '%s' "$cmds" | jq -c --arg n "$name" --arg fp "$(proofreuse_command_fp "$1" "$name")" '. + {($n): $fp}')
  done < <(printf '%s' "$1" | jq -j '(.commands // {}) | keys[] | . + "\u0000"')
  printf '%s' "$1" | jq -cS --argjson c "$cmds" '{commands: $c, single: ((.test_files.run // null) | tojson), list: ((.test_files.files // null) | tojson)}'
}

# proofcauses_form_causes OLD NEW: one line per part of the form that differs.
# An old form that is not an object (none was recorded) names nothing here.
proofcauses_form_causes() {
  printf '%s' "$1" | jq -e 'type == "object"' > /dev/null 2>&1 || return 0
  jq -nr --argjson o "$1" --argjson n "$2" '
    ((($o.commands // {}) + ($n.commands // {})) | keys[]
      | select(($o.commands // {})[.] != ($n.commands // {})[.]) | "the approved command \(.) changed"),
    (if $o.single != $n.single then "the single-file form changed" else empty end),
    (if $o.list != $n.list then "the list of test files changed" else empty end)'
}

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

# proofcauses_files RECORD HEAD STORE: the causes found in the files. Every
# recorded run is compared with the committed code HEAD.
proofcauses_files() {
  local key tree entries='[]' ch known
  [ -n "$2" ] || return 0
  while IFS=$'\t' read -r key tree; do
    ch=$(proofcauses_changes "$tree" "$2")
    [ -n "$ch" ] || continue
    entries=$(printf '%s' "$entries" | jq -c --slurpfile s <(printf '%s' "$3") --argjson c "$ch" --arg k "$key" \
      '. + [$s[0].runs[$k] | {key: $k, reads, dirs: (.dirs // []), changes: $c}]')
  done < <(printf '%s' "$3" | jq -r '.runs | to_entries[] | select(.value | type == "object" and (.tree | type) == "string") | [.key, .value.tree] | @tsv')
  known=$(proofcauses_known "$1" "$2")
  jq -nr --slurpfile e <(printf '%s' "$entries") --slurpfile s <(printf '%s' "$3") --argjson known "$known" '
    $e[0] as $e | ($e | map(select(.reads | type == "array"))) as $r
    | ($r | map(select(.key | startswith("file:")))) as $tests
    | ([$e[].changes[]] | map(.p) | unique) as $paths
    | ($known + [$s[0].runs | keys[] | select(startswith("file:")) | ltrimstr("file:")]) as $own
    | ([$r[].reads[]] | unique) as $read
    | ([$r[].dirs[] | if type == "object" then .path else . end] | unique) as $dirs
    | (if ($tests | length) >= 2 then
         [$paths[] | . as $p | select($tests | all(.reads | index($p)) and all(.changes | any(.p == $p and .s != "A")))
          | "\($p) changed, and every test file reads it"] else [] end),
      ([$e[].changes[] | select(.s == "A" or .s == "D")] | unique_by(.p)
        | map(select(.p as $p | ($read | index($p) | not) and ($own | index($p) | not)
                     and (($p | if test("/") then sub("/[^/]*$"; "") else "." end) as $d | $dirs | index($d) | not))
              | "\(.p) was \(if .s == "A" then "added" else "deleted" end), and no recorded run read it or listed its folder"))
    | .[]'
}

# proofcauses_find RECORD FULL HEAD: every cause for this proof, one per line,
# in a fixed order; nothing when the reuse rule may decide alone. FULL is 1 for
# vbw prove --full. HEAD is the tree of the committed code.
proofcauses_find() {
  local store probe old
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
  old=$(printf '%s' "$store" | jq -c '.form')
  proofcauses_form_causes "$old" "$(proofcauses_form "$1")"
  proofcauses_files "$1" "$3" "$store"
}
