#!/usr/bin/env bash
# vbw prove: run exactly what the user approved and record the evidence
# (docs/proof.md). Nothing unapproved ever executes.

# shellcheck source=checks.sh
. "$VBW_LIB/checks.sh"
# shellcheck source=proofcopy.sh
. "$VBW_LIB/proofcopy.sh"
# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"
# shellcheck source=proofcauses.sh
. "$VBW_LIB/proofcauses.sh"
# shellcheck source=testfiles.sh
. "$VBW_LIB/testfiles.sh"
# shellcheck source=cmd-next.sh
. "$VBW_LIB/cmd-next.sh"

VBW_FIX_CAP=3

cmd_prove() {
  local full=0
  case $# in
    0) ;;
    1) [ "$1" = --full ] || vbw_usage_error "usage: vbw prove [--full]"; full=1 ;;
    *) vbw_usage_error "usage: vbw prove [--full]" ;;
  esac
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  local causes record checks commands scope tree head ev at evf curf noreads mark="" n files='{}' tfs='{}' tfsum alln=0
  # This session's Stop hook waits while the mark names a live process (R98).
  if [ -n "$(vbw_session)" ]; then
    mark="$VBW_RUNTIME/proving.$(vbw_session)"
    printf '%s\n' "$$" > "$mark" && vbw_guard_add file "$mark"
  fi
  VBW_DIE_HOOK=proofcopy_warn_stale
  record=$(record_read)
  checks_begin "$record" strict
  # The file-system test first: where reads cannot be recorded nothing is reused.
  mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
  noreads=$(reads_probe "$VBW_RUNTIME" 2>&1) || true
  proofreuse_plan "$record" "$full"
  # Any cause (R168) runs every check, test file and command, and the summary names it.
  causes=$(proofcauses_find "$record" "$full" "$(vbw_head_tree 2> /dev/null)")
  if [ -n "$causes" ]; then alln=1; fi
  # With an approved single-file form the test files run in place of the test command.
  testfiles_plan "$record" "$alln"
  if [ -n "$causes" ]; then prove_plan_all "$record"; fi
  # A clone with no recorded run has nothing to compare with: no line gives a reason of its own.
  if printf '%s' "$PROOFREUSE_STORE" | jq -e '(.runs | length) == 0' > /dev/null; then WHY_CHECKS='{}' WHY_COMMANDS='{}'; fi
  at=$(vbw_now)
  # The marker stays until the evidence is recorded: a proof cut short reuses nothing next time.
  : > "$(proofreuse_marker)" || vbw_die "cannot write $(proofreuse_marker)"
  head=$(vbw_head_tree) || vbw_die "cannot fingerprint the committed code"
  checks='{}' commands='{}'
  if [ ${#TODO_CHECKS[@]} -gt 0 ] || [ "$TODO_COMMANDS" != '[]' ] || [ ${#TF_TODO[@]} -gt 0 ]; then
    n=${#TODO_CHECKS[@]}
    [ "$n" -ge ${#TF_TODO[@]} ] || n=${#TF_TODO[@]}
    [ "$n" -gt 0 ] || n=1
    proofcopy_create_slots "$(proofcopy_slots "$n")"
    proofcopy_verify "$CHECK_HASH" "$record"
    # Checks and commands run in clean copies; evidence and the record stay here.
    [ ${#TODO_CHECKS[@]} -eq 0 ] || checks=$(checks_run_all "$record" "${TODO_CHECKS[@]}")
    commands=$(prove_commands "$record" "$TODO_COMMANDS")
    [ ${#TF_TODO[@]} -eq 0 ] || files=$(testfiles_run "$record")
    checks_keep "$checks" "$commands" "$files"
    proofcopy_remove
  fi
  checks_end
  # The store keeps a read list as files, folders and git use; where the file
  # system records no reads no list is saved at all.
  checks=$(printf '%s' "$checks" | jq -c --argjson off "$([ -n "$noreads" ] && echo true || echo false)" "$PROVE_FLAT")
  commands=$(printf '%s' "$commands" | jq -c --argjson off "$([ -n "$noreads" ] && echo true || echo false)" "$PROVE_FLAT")
  files=$(printf '%s' "$files" | jq -c --argjson off "$([ -n "$noreads" ] && echo true || echo false)" "$PROVE_FLAT")
  proofreuse_save "$record" "$checks" "$commands" "$head" "$at"
  [ "$files" = '{}' ] || testfiles_save "$record" "$files" "$head" "$at"
  checks=$(prove_stamp "$record" check "$checks" "$at" "$WHY_CHECKS")
  commands=$(prove_stamp "$record" command "$commands" "$at" "$WHY_COMMANDS")
  # A reused pass ended as the check expects: its exit status is the expected one.
  checks=$(proofreuse_join "$(printf '%s' "$record" | jq -c '[.checks[].id]')" "$REUSE_CHECKS" "$checks" \
    | jq -c --slurpfile r <(printf '%s' "$record") 'to_entries | map(.key as $id | .value |= (del(.reads, .dirs, .git)
        | if .reused and .status == "pass" then .exit = ($r[0].checks[] | select(.id == $id) | .exit // 0) else . end)) | from_entries')
  commands=$(proofreuse_join "$PROVE_NAMES" "$REUSE_COMMANDS" "$commands" \
    | jq -c 'map_values(del(.reads, .dirs, .git) | if .reused and .status == "pass" then .exit = 0 else . end)')
  if testfiles_on "$record"; then
    tfs=$(testfiles_finish "$record" "$files" "$at")
    tfsum=$(testfiles_command "$record" "$tfs")
    commands=$(printf '%s' "$commands" | jq -c --argjson t "$tfsum" '. + {test: $t}')
  fi
  scope=$(prove_scope "$record")
  tree=$(vbw_code_tree) || vbw_die "cannot fingerprint the project files"
  # tree: the working folder (QA freshness, R12); head: the committed code the
  # checks ran on, so committing unproved edits later makes the proof stale.
  # full: nothing reused, no quick stand-in, every full command ran (R111).
  ev=$(jq -n --arg at "$at" --arg h "$CHECK_HASH" --argjson standin "$QUICK_STANDIN" --arg tree "$tree" --arg head "$head" \
    --slurpfile cf <(printf '%s' "$checks") --slurpfile mf <(printf '%s' "$commands") --slurpfile sf <(printf '%s' "$scope") --slurpfile tf <(printf '%s' "$tfs") \
    '$cf[0] as $c | $mf[0] as $m | $sf[0] as $s | $tf[0] as $t | {at: $at, contract: $h, tree: $tree, head: $head, checks: $c, commands: $m, test_files: $t, scope: $s,
      full: (($standin | not) and all($c[]; (.reused // false) | not) and all($m[]; (.reused // false) | not) and all($t[]; (.reused // false) | not)
             and all($m | to_entries[] | select(.key != "quick"); .value.status != "skipped")),
      passed: (all($c[]; .status == "pass") and all($m[]; .status == "pass" or .status == "skipped") and all($t[]; .status == "pass") and ($s | length) == 0)}')
  vbw_scratch_json evf "$ev"
  vbw_scratch_json curf "$(qa_combined "$record")"
  record_update "$VBW_JQ_DEFS$(cat "$VBW_LIB/prove.jq")" --slurpfile ev "$evf" --argjson cap "$VBW_FIX_CAP" --slurpfile cur "$curf" --arg at "$at"
  # The record as this proof leaves it, without the evidence (D296): the next prove's
  # "nothing committed" cause fires only while this fingerprint still holds (R175, R103).
  record_update '.evidence.record = $fp' --arg fp "$(jq -c 'del(.evidence)' "$VBW_RECORD" | vbw_sha256)"
  vbw_guard_drop "$evf"
  vbw_guard_drop "$curf"
  rm -f "$(proofreuse_marker)"
  # The evidence is part of the plan of record: commit it, so a proof never
  # leaves VBW's own file modified in the user's working tree.
  record_commit "chore(vbw): proof $(jq -r 'if .evidence.passed then "passed" else "not passed" end' "$VBW_RECORD")"
  # shellcheck disable=SC2034
  VBW_DIE_HOOK=; proofcopy_warn_stale
  [ -z "$mark" ] || vbw_guard_drop "$mark"
  prove_summary "$causes"
}

# Project commands: run only those whose exact argv the user approved, each as
# a unit of its own (alone: one at a time, in a slot copy), after the checks.
prove_commands() {
  local name argv a units='[]' skipped='{}' limit res
  limit=$(printf '%s' "$1" | jq -r --argjson d "$VBW_COMMAND_TIMEOUT" '.settings.command_timeout // $d')
  # $2: JSON array of the command names to run.
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then
      units=$(printf '%s' "$units" | jq -c --arg n "cmd-$name" --argjson t "$limit" \
        --slurpfile a <(printf '%s\0' "${argv[@]}" | jq -Rsc 'split("\u0000")[:-1]') \
        '. + [{name: $n, out: "\($n).out", argv: $a[0], timeout: $t, exit: 0, output: "", alone: true}]')
    else
      skipped=$(printf '%s' "$skipped" | jq -c --arg n "$name" '. + {($n): {status: "skipped", exit: null, seconds: 0, tail: "not approved"}}')
    fi
  done < <(printf '%s' "$1" | jq -j --argjson t "$2" '.commands | keys[] | select(. as $k | $t | index($k)) | . + "\u0000"')
  res=$(checks_run_units "$units")
  printf '%s' "$res" | jq -c --slurpfile s <(printf '%s' "$skipped") 'with_entries(.key |= ltrimstr("cmd-")) + $s[0]'
}

# prove_plan_all RECORD: nothing is reused (vbw prove --full, or a file system
# that records no reads): every check and command runs.
prove_plan_all() {
  REUSE_CHECKS='{}' REUSE_COMMANDS='{}' WHY_CHECKS='{}' WHY_COMMANDS='{}' TODO_CHECKS=() TODO_COMMANDS=$PROVE_NAMES
  local id
  while IFS= read -r id; do [ -z "$id" ] || TODO_CHECKS+=("$id"); done < <(printf '%s' "$1" | jq -r '.checks[].id')
}

# prove_stamp RECORD KIND RESULTS AT WHY: each result that really ran carries
# the fingerprint of its approved definition, the time it ran and the reason it
# had to run (WHY: JSON object name -> reason).
prove_stamp() {
  local name fp out="$3"
  while IFS= read -r -d '' name; do
    if [ "$2" = check ]; then fp=$(proofreuse_check_fp "$1" "$name"); else fp=$(proofreuse_command_fp "$1" "$name"); fi
    out=$(printf '%s' "$out" | jq -c --arg n "$name" --arg fp "$fp" --arg at "$4" --slurpfile w <(printf '%s' "$5") \
      '.[$n] += ({fp: $fp, at: $at} + (if $w[0][$n] and .[$n].status != "skipped" then {why: $w[0][$n]} else {} end))')
  done < <(printf '%s' "$3" | jq -j 'keys[] | . + "\u0000"')
  printf '%s\n' "$out"
}
# Scope: every commit whose VBW-Plan trailer names a plan in the record changes
# only that plan's files. Prints a JSON array of violations.
prove_scope() {
  local entry sha plan f
  {
    while IFS= read -r -d '' entry; do
      sha=${entry%%$'\x1f'*}
      plan=${entry#*$'\x1f'}
      plan=${plan%%$'\n'*}
      [ -n "$plan" ] || continue
      while IFS= read -r -d '' f; do
        printf '%s\x1f%s\x1f%s\n' "${sha:0:12}" "$plan" "$f"
      done < <(git diff-tree -z --no-commit-id --name-only -r --root "$sha")
    done < <(git log -z --format='%H%x1f%(trailers:key=VBW-Plan,valueonly)' 2> /dev/null)
  } | jq -R -s -c --slurpfile rec <(printf '%s' "$1") "$VBW_JQ_DEFS"'
    $rec[0] as $r
    | ($r.plans | map({key: .id, value: .files}) | from_entries) as $files
    | [split("\n")[] | select(length > 0) | split("\u001f") | select($files[.[1]] != null)
       | select(.[2] as $f | any($files[.[1]][]; covers($f)) | not)
       | "\(.[0]) (\(.[1])) changed \(.[2]), which is not in the plan"]'
}

# One screen: what ran, what it means, what is next. $1: the causes that ran everything, one per line.
prove_summary() {
  jq -r --arg causes "$1" --argjson d "$VBW_COMMAND_TIMEOUT" '(.settings.command_timeout // $d) as $limit | .evidence as $e
    | ($e.checks | to_entries[] | "  \(.key) \(.value.status)\(if .value.status == "fail" then " (exit \(.value.exit))" else "" end) \(.value.seconds)s\(if .value.reused then " reused (proof of \(.value.at))" elif .value.why then " ran: \(.value.why)" else "" end)"
        + (if .value.status == "pass" then "" else ": " + (.value.tail | split("\n") | last // "") end)),
      ($e.commands | to_entries[] | select(.value.of_files | not) | "  \(.key) \(.value.status)\(if .value.status == "skipped" then ": not approved" else " \(.value.seconds)s\(if .value.reused then " reused (proof of \(.value.at))" elif .value.why then " ran: \(.value.why)" else "" end)" end)"),
      (($e.test_files // {}) | to_entries[] | "  \(.key) \(.value.status)\(if .value.status == "fail" then " (exit \(.value.exit))" else "" end) \(.value.seconds)s\(if .value.reused then " reused (proof of \(.value.at))" elif .value.why then " ran: \(.value.why)" else "" end)"
        + (if .value.status == "pass" then "" else ": " + (.value.tail | split("\n") | last // "") end)),
      ([$causes | split("\n")[] | select(length > 0)] as $c
        | if ($c | length) == 1 then "  ran everything: \($c[0])"
          elif ($c | length) > 1 then "  ran everything, because:", ($c[] | "  - \(.)") else empty end),
      "  checks: \([$e.checks[] | select(.reused | not)] | length) ran, \([$e.checks[] | select(.reused)] | length) reused",
      "  test files: \([($e.test_files // {})[] | select(.reused | not)] | length) ran, \([($e.test_files // {})[] | select(.reused)] | length) reused",
      (if ($e.commands.test // null) != null and ($e.commands.test.of_files | not) and ($e.commands.test.reused | not) and ($e.commands.test.status != "skipped")
         then "  test command ran whole: no single-file form is declared" else empty end),
      (if ($e.commands.test // null) != null and $e.commands.test.of_files and (($e.test_files // {}) | length) == 0
         then "  test command: \($e.commands.test.tail)" else empty end),
      (($e.commands + ($e.test_files // {})) | to_entries[] | select(.value.status == "timeout" and (.value.of_files | not))
        | "  \(.key) stopped by its time limit (\($limit) s); raise it with vbw config set command_timeout SECONDS"),
      (if $e.full != false then "  proof: full" else
        "  proof: partial [" + ([ (if any(($e.checks[], $e.commands[], ($e.test_files // {})[]); .reused) then "results reused" else empty end),
          (if ($e.commands | has("quick") and (.quick.status != "skipped") and (has("test") | not)) then "quick stood in for the test command" else empty end),
          ($e.commands | to_entries[] | select(.key != "quick" and .value.status == "skipped") | "\(.key) not approved") ] | join(", ")) + "]" end),
      (if ($e.scope | length) == 0 then "  scope ok" else ($e.scope[] | "  scope: " + .) end),
      (.requirements[] | select(.proof == "auto") | "\(.id) \(.status)"),
      (.fixes[] | select(.status == "open" or .status == "escalated") | "\(.id) \(.status) (\(.req // .command), attempts \(.attempts)): \(.note)"),
      (if $e.passed then "proved" else "not proved" end)' "$VBW_RECORD"
  jq -e '.evidence.passed' "$VBW_RECORD" > /dev/null
}
