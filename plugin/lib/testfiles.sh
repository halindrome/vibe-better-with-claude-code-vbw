#!/usr/bin/env bash
# Test files as units of a proof (docs/proof.md, R167). With an approved
# single-file form (the spec's "## Test files": a run argv naming {file} once
# and git pathspecs) each test file is a unit of its own, run in a slot copy
# with its read list saved and reused by the one reuse rule of proofreuse.sh.
# The test command and the quick command then do not run (D179: no test file
# runs twice in one proof; a file an approved check runs runs only as that
# check). Without a form the test command runs whole.

# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"

# testfiles_on RECORD: succeed when the record carries a form. Called after
# checks_begin, which dies unless the contract, and so the form, is approved.
testfiles_on() { printf '%s' "$1" | jq -e 'has("test_files")' > /dev/null; }

# testfiles_id PATH: the short name of a test file's unit (a file name cannot
# be one: the gate and the output folder take it as a file name).
testfiles_id() { printf 'tf-%s\n' "$(printf '%s' "$1" | vbw_sha256 | cut -c1-12)"; }

# testfiles_list RECORD: the test files, NUL separated: the committed files the
# declared pathspecs match, minus every file the run of an approved check names.
testfiles_list() {
  local specs=() a
  while IFS= read -r -d '' a; do specs+=("$a"); done < <(printf '%s' "$1" | jq -j '.test_files.files[] + "\u0000"')
  [ ${#specs[@]} -gt 0 ] || return 0
  git -C "$VBW_ROOT" ls-files -z -- ${specs[@]+"${specs[@]}"} \
    | jq -Rs -j --slurpfile r <(printf '%s' "$1") '[$r[0].checks[].run[]] as $run
        | split("\u0000")[] | . as $p | select(length > 0 and (any($run[]; . == $p) | not)) | . + "\u0000"'
}

# testfiles_argv RECORD PATH: the form's argv for one test file, NUL separated.
testfiles_argv() {
  printf '%s' "$1" | jq -j --arg f "$2" '.test_files.run[] | split("{file}") | join($f) | . + "\u0000"'
}

# testfiles_limit RECORD: the seconds a test file may take (as a project command).
testfiles_limit() {
  printf '%s' "$1" | jq -r --argjson d "$VBW_COMMAND_TIMEOUT" '.settings.command_timeout // $d'
}

# testfiles_fp RECORD PATH: fingerprint of a test file's approved definition.
testfiles_fp() {
  local argv=() a
  argv+=("$(testfiles_limit "$1")")
  while IFS= read -r -d '' a; do argv+=("$a"); done < <(testfiles_argv "$1" "$2")
  vbw_sha256_argv "${argv[@]}"
}

# testfiles_plan RECORD ALL: after proofreuse_plan. With a form, takes the test
# and quick commands out of the proof and sets TF_PATHS (the test files, an
# array), TF_REUSE (reused results, JSON path -> result), TF_TODO (array of
# the paths that run) and TF_WHY (JSON path -> why it runs). ALL (1): nothing
# is reused. Without a form all of them are empty.
testfiles_plan() {
  local record="$1" off='' head='' p fp why
  TF_PATHS=() TF_TODO=() TF_REUSE='{}' TF_WHY='{}'
  testfiles_on "$record" || return 0
  PROVE_NAMES=$(printf '%s' "$PROVE_NAMES" | jq -c '. - ["test", "quick"]')
  TODO_COMMANDS=$(printf '%s' "$TODO_COMMANDS" | jq -c '. - ["test", "quick"]')
  REUSE_COMMANDS=$(printf '%s' "$REUSE_COMMANDS" | jq -c 'del(.test, .quick)')
  WHY_COMMANDS=$(printf '%s' "$WHY_COMMANDS" | jq -c 'del(.test, .quick)')
  # shellcheck disable=SC2034 # read by cmd_prove
  QUICK_STANDIN=false
  while IFS= read -r -d '' p; do TF_PATHS+=("$p"); done < <(testfiles_list "$record")
  if [ "$2" != 1 ]; then
    off=$(proofreuse_allowed) || true
    if [ -z "$off" ]; then
      head=$(vbw_head_tree) || head=
      [ -n "$head" ] || off='no committed code'
    fi
  fi
  for p in ${TF_PATHS[@]+"${TF_PATHS[@]}"}; do
    fp=$(testfiles_fp "$record" "$p")
    why=$off
    [ "$2" = 1 ] || [ -n "$why" ] || why=$(proofreuse_reason "file:$p" "$fp" "$head") || true
    if [ "$2" != 1 ] && [ -z "$why" ]; then
      TF_REUSE=$(printf '%s' "$TF_REUSE" | jq -c --arg p "$p" --argjson r "$(proofreuse_result "file:$p")" '. + {($p): $r}')
    else
      TF_TODO+=("$p")
      [ "$2" = 1 ] || TF_WHY=$(printf '%s' "$TF_WHY" | jq -c --arg p "$p" --arg w "$why" '. + {($p): $w}')
    fi
  done
  # A clone with no recorded run has nothing to compare with: no line gives a reason of its own.
  if printf '%s' "$PROOFREUSE_STORE" | jq -e '(.runs | length) == 0' > /dev/null; then TF_WHY='{}'; fi
}

# testfiles_run RECORD: run the test files in TF_TODO, each as a unit of its
# own (several at a time, in slot copies); {path: result}, each result with
# "id" (its output file's name) and its read list.
testfiles_run() {
  local units='[]' p a limit res
  limit=$(testfiles_limit "$1")
  for p in ${TF_TODO[@]+"${TF_TODO[@]}"}; do
    units=$(printf '%s' "$units" | jq -c --arg n "$(testfiles_id "$p")" --argjson t "$limit" \
      --slurpfile a <(testfiles_argv "$1" "$p" | jq -Rsc 'split("\u0000")[:-1]') \
      '. + [{name: $n, out: "\($n).out", argv: $a[0], timeout: $t, exit: 0, output: "", alone: false}]')
  done
  res=$(checks_run_units "$units")
  for p in ${TF_TODO[@]+"${TF_TODO[@]}"}; do
    a=$(testfiles_id "$p")
    printf '%s\0' "$p" "$a"
  done | jq -Rs -c --slurpfile r <(printf '%s' "$res") 'split("\u0000")[:-1] as $l
    | [range(0; $l | length; 2) | {p: $l[.], id: $l[. + 1]}]
    | map({key: .p, value: ($r[0][.id] + {id: .id})}) | from_entries'
}

# testfiles_save RECORD FILES TREE AT: record the runs that really happened in
# the store (read list included, and the test file itself: a changed test file
# always runs). Through proofreuse_merge, under the store's lock.
testfiles_save() {
  local new p fp
  new='{}'
  while IFS= read -r -d '' p; do
    fp=$(testfiles_fp "$1" "$p")
    new=$(printf '%s' "$new" | jq -c --slurpfile r <(printf '%s' "$2") --arg p "$p" --arg fp "$fp" --arg tree "$3" --arg at "$4" \
      '$r[0][$p] as $x | if $x.status == "skipped" or $x.status == "waiting" then . else
        . + {("file:" + $p): {fp: $fp, tree: $tree, status: $x.status, at: $at, seconds: $x.seconds, tail: ($x.tail // ""),
          reads: (if $x.reads == null then null else ($x.reads + [$p] | unique) end), dirs: ($x.dirs // []), git: ($x.git // false)}} end')
  done < <(printf '%s' "$2" | jq -j 'keys[] | . + "\u0000"')
  proofreuse_merge "$new"
}

# testfiles_finish RECORD RESULTS AT: the results of the test files for the
# evidence, in the files' order: the new ones stamped with their definition's
# fingerprint, the time and the reason they ran, joined with the reused ones.
testfiles_finish() {
  local p out="$2" order
  while IFS= read -r -d '' p; do
    out=$(printf '%s' "$out" | jq -c --arg p "$p" --arg fp "$(testfiles_fp "$1" "$p")" --arg at "$3" --slurpfile w <(printf '%s' "$TF_WHY") \
      '.[$p] += ({fp: $fp, at: $at} + (if $w[0][$p] and .[$p].status != "skipped" then {why: $w[0][$p]} else {} end))')
  done < <(printf '%s' "$2" | jq -j 'keys[] | . + "\u0000"')
  order=$(printf '%s\0' ${TF_PATHS[@]+"${TF_PATHS[@]}"} | jq -Rsc 'split("\u0000")[:-1]')
  proofreuse_join "$order" "$TF_REUSE" "$out" \
    | jq -c 'map_values(del(.reads, .dirs, .git, .id) | if .reused and .status == "pass" then .exit = 0 else . end)'
}

# testfiles_command RECORD RESULTS: the test command's place in the evidence when the
# test files ran in its stead: one result, passing when every test file passed
# (reused when every one was), so a failing test file fails the proof, opens a
# fix for the test command and QA sees the suite's state.
testfiles_command() {
  printf '%s' "$2" | jq -c --arg run "$(printf '%s' "$1" | jq -r '.test_files.run | join(" ")')" '
    [.[]] as $r | [$r[] | select(.status != "pass")] as $bad
    | {status: (if ($bad | length) == 0 then "pass" elif all($bad[]; .status == "timeout") then "timeout" else "fail" end),
       exit: (if ($bad | length) == 0 then 0 else null end), seconds: ([$r[].seconds // 0] | add // 0),
       tail: ([to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join("\n")),
       command: ($run + " (one test file per run)"), of_files: true}
      + (if ($r | length) > 0 and all($r[]; .reused) then {reused: true, at: ([$r[].at] | max)} else {} end)'
}
