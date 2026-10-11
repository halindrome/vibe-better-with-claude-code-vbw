#!/usr/bin/env bash
# The one reuse rule of vbw prove and vbw fix done (docs/proof.md, R166) and
# the clone's store of recorded runs. A unit (a check, a project command or a
# test file) is run again only when something it depends on changed; its read
# list, written down by the run itself, says what it depends on.

# proofreuse_check_fp RECORD ID: fingerprint of a check's approved definition.
proofreuse_check_fp() {
  printf '%s' "$1" | jq -cS --arg id "$2" '.checks[] | select(.id == $id)
    | {id, req, run, exit, output, timeout, alone, files}' | vbw_sha256
}

# proofreuse_command_fp RECORD NAME: fingerprint of a project command's argv
# and the time limit it runs under (settings.command_timeout, else the default).
proofreuse_command_fp() {
  local argv=() a
  argv+=("$(printf '%s' "$1" | jq -r --argjson d "$VBW_COMMAND_TIMEOUT" '.settings.command_timeout // $d')")
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$1" | jq -j --arg n "$2" '.commands[$n][] + "\u0000"')
  vbw_sha256_argv ${argv[@]+"${argv[@]}"}
}

# proofreuse_marker: the unfinished marker (present while a proof runs, and
# left behind by one that was interrupted or failed to record).
proofreuse_marker() { printf '%s/prove.unfinished\n' "$VBW_RUNTIME"; }

# proofreuse_allowed: succeed when this proof may reuse anything; print why
# not otherwise. Not while an earlier proof is unfinished, and (D173) not when
# nothing at all changed since the last proof (it is the last commit, VBW's own
# files are clean and the working folder is the committed code): a second
# prove is a deliberate re-run, as when something outside the committed code
# (installed dependencies, ignored files) changed.
proofreuse_allowed() {
  if [ -e "$(proofreuse_marker)" ]; then
    printf 'the last proof was cut short\n'
    return 1
  fi
  if [ "$(git -C "$VBW_ROOT" log -1 --format=%s 2> /dev/null)" = 'chore(vbw): proof passed' ] \
    && [ -z "$(git -C "$VBW_ROOT" status --porcelain -z -- .vbw 2> /dev/null | tr -d '\000')" ] \
    && [ "$(vbw_code_tree)" = "$(vbw_head_tree)" ]; then
    printf 'proving again with nothing committed\n'
    return 1
  fi
}

# The store of recorded runs lives in the clone, never in the record (it
# changes on every run and would make the record's history noise):
# $(git common dir)/vbw/runs.json, {runs: {"check:ID" | "command:NAME" |
# "file:PATH": {fp, tree, status, at, seconds, tail, reads, dirs, git}}, form}.
# fp: fingerprint of the unit's approved definition; tree: the committed code
# it ran on; reads: the project files it opened (null: none was written down);
# dirs: the folders it listed; git: it read the project through git. form: the
# fingerprint of the approved commands and test-file form of the last recorded
# run. A missing or damaged store means nothing is reused.
proofreuse_store_file() {
  local common
  common=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || vbw_die "not a git repository"
  printf '%s/vbw/runs.json\n' "$common"
}

# proofreuse_store_read: the store, or an empty one when it is missing or damaged.
proofreuse_store_read() {
  jq -c 'if type == "object" and (.runs | type) == "object" then {runs, form: (.form // null)} else error("shape") end' \
    "$(proofreuse_store_file)" 2> /dev/null || printf '{"runs":{},"form":null}\n'
}

# proofreuse_store_form: the form of the last recorded run (a JSON object; a
# plain text from an older store prints as it is), or nothing.
proofreuse_store_form() { proofreuse_store_read | jq -r '.form // empty | if type == "string" then . else tojson end'; }

# proofreuse_merge NEW [FORM]: the one writer of the store. NEW (a JSON object
# key -> run) is merged over the recorded runs; FORM, when given, replaces the
# form (JSON text is kept as an object, anything else as text). The
# read-modify-write runs under a lock beside the file and ends in an atomic move.
proofreuse_merge() {
  local file lock tmp
  file=$(proofreuse_store_file)
  mkdir -p "${file%/*}" || vbw_die "cannot create ${file%/*}"
  lock="${file%.json}.lock"
  vbw_lock_take "$lock" "runs"
  tmp=$(mktemp "${file%/*}/runs.XXXXXX") || vbw_die "cannot create a temporary file in ${file%/*}"
  vbw_guard_add file "$tmp"
  proofreuse_store_read | jq -c --slurpfile nw <(printf '%s' "$1") --arg form "${2-}" --argjson keep "$([ $# -ge 2 ] && echo false || echo true)" \
    '{runs: (.runs + $nw[0]), form: (if $keep then .form else ($form | try fromjson catch $form) end)}' > "$tmp" && mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$lock"
}

# proofreuse_save RECORD CHECKS COMMANDS TREE AT FORM (JSON text): record the
# runs that really happened (CHECKS and COMMANDS: JSON objects name -> result,
# with the read list the runner collected) on the committed code TREE. A unit
# that was not run (skipped, waiting) leaves its earlier run alone.
proofreuse_save() {
  local new='{}' kind name fp res
  for kind in check command; do
    res="$2"
    [ "$kind" = check ] || res="$3"
    while IFS= read -r -d '' name; do
      if [ "$kind" = check ]; then fp=$(proofreuse_check_fp "$1" "$name"); else fp=$(proofreuse_command_fp "$1" "$name"); fi
      new=$(printf '%s' "$new" | jq -c --slurpfile r <(printf '%s' "$res") --arg k "$kind:$name" --arg n "$name" --arg fp "$fp" --arg tree "$4" --arg at "$5" \
        '$r[0][$n] as $x | if $x.status == "skipped" or $x.status == "waiting" then . else
          . + {($k): {fp: $fp, tree: $tree, status: $x.status, at: $at, seconds: $x.seconds, tail: ($x.tail // ""),
            reads: ($x.reads // null), dirs: ($x.dirs // []), git: ($x.git // false)}} end')
    done < <(printf '%s' "$res" | jq -j 'keys[] | . + "\u0000"')
  done
  proofreuse_merge "$new" "$6"
}

# proofreuse_reason KEY FP HEAD: the one reuse rule. Succeeds, printing
# nothing, when the unit's pass may be reused: its last result passed, its
# definition fingerprint FP is unchanged, it has a read list and did not read
# through git, and one git diff-tree between the tree it ran on and the
# committed code HEAD shows no file of its read list changed or deleted and no
# file added to or removed from a folder it listed. Otherwise fails and prints
# the reason. Reads the store from PROOFREUSE_STORE (a JSON text).
proofreuse_reason() {
  local entry reason diff
  entry=$(printf '%s' "$PROOFREUSE_STORE" | jq -c --arg k "$1" '.runs[$k] // empty | select(type == "object")') || entry=
  if [ -z "$entry" ]; then printf 'never passed\n'; return 1; fi
  reason=$(printf '%s' "$entry" | jq -r --arg fp "$2" '
    if .status != "pass" then "last result failed"
    elif (.reads | type) != "array" then "no read list"
    elif .fp != $fp then "definition changed"
    elif .git == true then "reads the project through git"
    else empty end') || reason='no read list'
  if [ -n "$reason" ]; then printf '%s\n' "$reason"; return 1; fi
  diff=$(git -C "$VBW_ROOT" diff-tree -z -r --no-renames --name-status "$(printf '%s' "$entry" | jq -r .tree)" "$3" 2> /dev/null | tr '\0' '\n'; exit "${PIPESTATUS[0]}") \
    || { printf 'the code it ran on is unknown\n'; return 1; }
  [ -n "$diff" ] || return 0
  reason=$(printf '%s\n' "$diff" | jq -R -s -r --slurpfile e <(printf '%s' "$entry") '
    $e[0] as $e | ($e.reads | map({key: ., value: true}) | from_entries) as $reads | $e.dirs as $dirs
    | [split("\n")[] | select(length > 0)] as $l
    | [range(0; $l | length; 2) | {s: $l[.][0:1], p: $l[. + 1]}]
    | (map(select($reads[.p]) | if .s == "D" then "\(.p) deleted" else "\(.p) changed" end)
       + map(select(.s == "A" or .s == "D") | (.p | if test("/") then sub("/[^/]*$"; "") else "." end) as $d
             | select($dirs | index($d)) | "\($d) listing changed")) | first // empty')
  if [ -n "$reason" ]; then printf '%s\n' "$reason"; return 1; fi
}

# proofreuse_names RECORD FULL: sets PROVE_NAMES (JSON array of the command
# names this proof covers) and QUICK_STANDIN (true when the approved quick
# command stands in for the test command). Full: every command but quick. Plain:
# an approved quick replaces test; a quick that is named but not approved is
# listed (and so reported skipped) and the test command runs (R111).
proofreuse_names() {
  local argv=() a
  # shellcheck disable=SC2034 # read by cmd_prove
  QUICK_STANDIN=false
  if [ "$2" = 1 ]; then
    PROVE_NAMES=$(printf '%s' "$1" | jq -c '.commands | keys - ["quick"]')
    return 0
  fi
  PROVE_NAMES=$(printf '%s' "$1" | jq -c '.commands | keys')
  printf '%s' "$1" | jq -e '.commands | has("quick") and has("test")' > /dev/null || return 0
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$1" | jq -j '.commands.quick[] + "\u0000"')
  if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then
    # shellcheck disable=SC2034 # read by cmd_prove
    QUICK_STANDIN=true
    PROVE_NAMES=$(printf '%s' "$PROVE_NAMES" | jq -c '. - ["test"]')
  fi
}

# proofreuse_plan RECORD [FULL]: FULL (1) only picks which commands belong to a
# full proof; the reuse rule is the same. Sets REUSE_CHECKS and REUSE_COMMANDS
# (the reused results, as JSON objects), TODO_CHECKS (array) and TODO_COMMANDS
# (JSON array of names), which are what has to run, and WHY_CHECKS and
# WHY_COMMANDS (JSON objects name -> the reason it has to run).
proofreuse_plan() {
  local record="$1" id name fp why head='' off=''
  proofreuse_names "$record" "${2:-0}"
  REUSE_CHECKS='{}' REUSE_COMMANDS='{}' TODO_CHECKS=() TODO_COMMANDS='[]' WHY_CHECKS='{}' WHY_COMMANDS='{}'
  PROOFREUSE_STORE=$(proofreuse_store_read)
  off=$(proofreuse_allowed) || true
  if [ -z "$off" ]; then
    head=$(vbw_head_tree) || head=
    [ -n "$head" ] || off='no committed code'
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    fp=$(proofreuse_check_fp "$record" "$id")
    why=$off
    [ -n "$why" ] || why=$(proofreuse_reason "check:$id" "$fp" "$head") || true
    if [ -z "$why" ]; then
      REUSE_CHECKS=$(printf '%s' "$REUSE_CHECKS" | jq -c --arg id "$id" --argjson r "$(proofreuse_result "check:$id")" '. + {($id): $r}')
    else
      TODO_CHECKS+=("$id")
      WHY_CHECKS=$(printf '%s' "$WHY_CHECKS" | jq -c --arg id "$id" --arg w "$why" '. + {($id): $w}')
    fi
  done < <(printf '%s' "$record" | jq -r '.checks[].id')
  while IFS= read -r -d '' name; do
    fp=$(proofreuse_command_fp "$record" "$name")
    why=$off
    [ -n "$why" ] || why=$(proofreuse_reason "command:$name" "$fp" "$head") || true
    if [ -z "$why" ]; then
      REUSE_COMMANDS=$(printf '%s' "$REUSE_COMMANDS" | jq -c --arg n "$name" --argjson r "$(proofreuse_result "command:$name")" '. + {($n): $r}')
    else
      TODO_COMMANDS=$(printf '%s' "$TODO_COMMANDS" | jq -c --arg n "$name" '. + [$n]')
      WHY_COMMANDS=$(printf '%s' "$WHY_COMMANDS" | jq -c --arg n "$name" --arg w "$why" '. + {($n): $w}')
    fi
  done < <(printf '%s' "$PROVE_NAMES" | jq -j '.[] + "\u0000"')
}

# proofreuse_result KEY: a stored run as a reused result (it keeps the time it
# really ran, and its read list for the next proof).
proofreuse_result() {
  printf '%s' "$PROOFREUSE_STORE" | jq -c --arg k "$1" '.runs[$k] | {status, exit: null, seconds, tail, at, fp, reads, dirs, git, reused: true}'
}

# proofreuse_join ORDER REUSED NEW: one object in ORDER (a JSON array of names).
proofreuse_join() {
  jq -nc --slurpfile o <(printf '%s' "$1") --slurpfile a <(printf '%s' "$2") --slurpfile b <(printf '%s' "$3") \
    '$a[0] as $a | $b[0] as $b | $o[0] | map({key: ., value: ($b[.] // $a[.])}) | from_entries'
}
