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
# shellcheck source=proofsteps.sh
. "$VBW_LIB/proofsteps.sh"
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
  local causes record checks commands scope undone tree head ev at evf curf noreads mark="" n files='{}' tfs='{}' tfsum alln=0 t0 own
  # This session's Stop hook waits while the mark names a live process (R98).
  if [ -n "$(vbw_session)" ]; then
    mark="$VBW_RUNTIME/proving.$(vbw_session)"
    printf '%s\n' "$$" > "$mark" && vbw_guard_add file "$mark"
  fi
  VBW_DIE_HOOK=proofcopy_warn_stale
  prooftime_begin
  record=$(record_read)
  checks_begin "$record" strict
  # The file-system test first: where reads cannot be recorded nothing is reused.
  mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
  proofsteps_clean
  noreads=$(reads_probe "$VBW_RUNTIME" 2>&1) || true
  slots_hold vbw:plan || true
  t0=$(prooftime_clock)
  proofreuse_plan "$record" "$full"
  # Any cause (R168) runs every check, test file and command, and the summary names it.
  causes=$(proofcauses_find "$record" "$full" "$(vbw_head_tree 2> /dev/null)")
  if [ -n "$causes" ]; then alln=1; fi
  # With an approved single-file form the test files run in place of the test command.
  testfiles_plan "$record" "$alln"
  if [ -n "$causes" ]; then prove_plan_all "$record"; fi
  # A clone with no recorded run has nothing to compare with: no line gives a reason of its own.
  if printf '%s' "$PROOFREUSE_STORE" | jq -e '(.runs | length) == 0' > /dev/null; then WHY_CHECKS='{}' WHY_COMMANDS='{}'; fi
  prooftime_span planning "$t0"
  slots_release vbw:plan
  at=$(vbw_now)
  # The marker stays until the evidence is recorded: a proof cut short reuses nothing next time.
  : > "$(proofreuse_marker)" || vbw_die "cannot write $(proofreuse_marker)"
  head=$(vbw_head_tree) || vbw_die "cannot fingerprint the committed code"
  checks='{}' commands='{}'
  if [ ${#TODO_CHECKS[@]} -gt 0 ] || [ "$TODO_COMMANDS" != '[]' ] || [ ${#TF_TODO[@]} -gt 0 ]; then
    n=${#TODO_CHECKS[@]}
    [ "$n" -ge ${#TF_TODO[@]} ] || n=${#TF_TODO[@]}
    [ "$n" -gt 0 ] || n=1
    slots_hold vbw:copies || true
    t0=$(prooftime_clock)
    proofcopy_create_slots "$(proofcopy_slots "$n")"
    prooftime_span copies "$t0"
    slots_release vbw:copies
    proofsteps_begin "$(prove_units "$record")" "$(prove_unit_names "$record")"
    proofcopy_verify "$CHECK_HASH" "$record"
    # Checks and commands run in clean copies; evidence and the record stay here.
    [ ${#TODO_CHECKS[@]} -eq 0 ] || checks=$(checks_run_all "$record" "${TODO_CHECKS[@]}")
    commands=$(prove_commands "$record" "$TODO_COMMANDS")
    [ ${#TF_TODO[@]} -eq 0 ] || files=$(testfiles_run "$record")
    proofsteps_units "$checks" "$commands" "$files"
    checks_keep "$checks" "$commands" "$files"
    proofcopy_remove
  fi
  checks_end
  # The store keeps a read list as files, folders and git use; where the file
  # system records no reads no list is saved at all.
  checks=$(printf '%s' "$checks" | jq -c --argjson off "$([ -n "$noreads" ] && echo true || echo false)" "$PROVE_FLAT")
  commands=$(printf '%s' "$commands" | jq -c --argjson off "$([ -n "$noreads" ] && echo true || echo false)" "$PROVE_FLAT")
  files=$(printf '%s' "$files" | jq -c --argjson off "$([ -n "$noreads" ] && echo true || echo false)" "$PROVE_FLAT")
  slots_hold vbw:save || true
  t0=$(prooftime_clock)
  proofreuse_save "$record" "$checks" "$commands" "$head" "$at"
  [ "$files" = '{}' ] || testfiles_save "$record" "$files" "$head" "$at"
  prooftime_span saving "$t0"
  slots_release vbw:save
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
  undone=$(printf '%s' "$scope" | jq -c '.undone')
  scope=$(printf '%s' "$scope" | jq -c '.scope')
  tree=$(vbw_code_tree) || vbw_die "cannot fingerprint the project files"
  # tree: the working folder (QA freshness, R12); head: the committed code the
  # checks ran on, so committing unproved edits later makes the proof stale.
  # full: nothing reused, no quick stand-in, every full command ran (R111).
  # The split so far; own.record is added once the record is written, after the wall time is read.
  own=$(prooftime_total)
  # The causes grow with a commit (one per unseen file): through a file, never as an argument.
  ev=$(jq -n --arg at "$at" --arg h "$CHECK_HASH" --argjson standin "$QUICK_STANDIN" --arg tree "$tree" --arg head "$head" \
    --slurpfile cf <(printf '%s' "$checks") --slurpfile mf <(printf '%s' "$commands") --slurpfile sf <(printf '%s' "$scope") --slurpfile uf <(printf '%s' "$undone") --slurpfile tf <(printf '%s' "$tfs") \
    --argjson own "$own" --rawfile causes <(printf '%s' "$causes") \
    '$cf[0] as $c | $mf[0] as $m | $sf[0] as $s | $uf[0] as $u | $tf[0] as $t | {at: $at, contract: $h, tree: $tree, head: $head, checks: $c, commands: $m, test_files: $t, scope: $s, undone: $u, own: $own,
      causes: ($causes | split("\n") | map(select(length > 0))),
      full: (($standin | not) and all($c[]; (.reused // false) | not) and all($m[]; (.reused // false) | not) and all($t[]; (.reused // false) | not)
             and all($m | to_entries[] | select(.key != "quick"); .value.status != "skipped")),
      passed: (all($c[]; .status == "pass") and all($m[]; .status == "pass" or .status == "skipped") and all($t[]; .status == "pass") and ($s | length) == 0)}')
  vbw_scratch_json evf "$ev"
  vbw_scratch_json curf "$(qa_combined "$record")"
  t0=$(prooftime_clock)
  record_update "$VBW_JQ_DEFS$(cat "$VBW_LIB/prove.jq")" --slurpfile ev "$evf" --argjson cap "$VBW_FIX_CAP" --slurpfile cur "$curf" --arg at "$at"
  prooftime_span record "$t0"
  # The record as this proof leaves it, without the evidence (D296): the next prove's
  # "nothing committed" cause fires only while this fingerprint still holds (R175, R103).
  record_update '.evidence.record = $fp | .evidence.own.record = $rec' --arg fp "$(jq -c 'del(.evidence)' "$VBW_RECORD" | vbw_sha256)" \
    --argjson rec "$(prooftime_total | jq -c '.record')"
  vbw_guard_drop "$evf"
  vbw_guard_drop "$curf"
  rm -f "$(proofreuse_marker)"
  # The evidence is part of the plan of record: commit it, so a proof never
  # leaves VBW's own file modified in the user's working tree.
  record_commit "chore(vbw): proof $(jq -r 'if .evidence.passed then "passed" else "not passed" end' "$VBW_RECORD")"
  proofsteps_end
  prooftime_end
  # shellcheck disable=SC2034
  VBW_DIE_HOOK=; proofcopy_warn_stale
  [ -z "$mark" ] || vbw_guard_drop "$mark"
  local rc=0
  prove_summary "$causes" || rc=$?
  slots_say
  return "$rc"
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

# prove_unit_names RECORD: the names of the units this proof runs (check:ID,
# file:PATH, command:NAME), as a JSON array: what prove_units counts.
prove_unit_names() {
  local c
  {
    for c in ${TODO_CHECKS[@]+"${TODO_CHECKS[@]}"}; do
      printf '%s\n' "${CHECK_HELD:-}" | grep -qx -- "$c" || printf 'check:%s\n' "$c"
    done
    for c in ${TF_TODO[@]+"${TF_TODO[@]}"}; do printf 'file:%s\n' "$c"; done
    proofsteps_command_names "$1" "$TODO_COMMANDS" | sed 's/^/command:/'
  } | proofsteps_names
}

# prove_units RECORD: how many units this proof runs: the checks that are not held,
# the approved project commands and the test files.
prove_units() {
  local c n=0
  for c in ${TODO_CHECKS[@]+"${TODO_CHECKS[@]}"}; do
    printf '%s\n' "${CHECK_HELD:-}" | grep -qx -- "$c" || n=$((n + 1))
  done
  printf '%s\n' "$((n + $(proofsteps_commands "$1" "$TODO_COMMANDS") + ${#TF_TODO[@]}))"
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
prove_stamp() { proofreuse_annotate "$@"; }
# Scope: every commit whose VBW-Plan trailer names a plan of the current
# milestone changes only that plan's files. A shipped milestone's commits were
# judged by its own proofs; today's record can no longer judge them (T162).
# A commit exactly undone by a later standing commit is not judged (R204).
#
# git lists the history once, jq does the rest: the shell runs the same
# commands whatever its length (R204). PROVE_SCOPE_PARSE_JQ reads git's stream
# (git log -z --topo-order --raw: per commit a header "hash, unit separator,
# trailer values", then per changed path ":old-mode new-mode old-blob new-blob
# status" and the path; a merge lists nothing) into commits newest first,
# [{h, p (first VBW-Plan value or ""), f (paths), fwd, bwd}]: fwd is the change
# as "path old-pair new-pair" entries in git's path order, bwd the same with
# the pairs swapped, so B undoes A exactly when B's bwd is A's fwd. Records are
# built without growing a string or an array inside the state, so a commit of
# 20,000 files costs no more per path than a small one.
# shellcheck disable=SC2016 # a jq program
PROVE_SCOPE_PARSE_JQ='split("\u0000") as $t
  | [foreach range(0; $t | length) as $k ({e: null, n: -1, o: null};
      if .e != null then .o = {k: .n, f: $t[$k], e: .e} | .e = null
      else ($t[$k] | sub("^\n+"; "")) as $x
        | if $x == "" then .o = null
          elif ($x | startswith(":")) then .e = ($x[1:] | split(" ")) | .o = null
          else .n += 1 | ($x | index("\u001f")) as $u
            | .o = {k: .n, h: $x[0:$u], p: ($x[$u + 1:] | split("\n")[0] // "")}
          end
      end;
      .o // empty)] as $l
  | (reduce ($l | map(select(has("f"))) | group_by(.k))[] as $g ({};
      .[$g[0].k | tostring] = {f: ($g | map(.f)),
        fwd: ($g | map("\(.f)\u001f\(.e[0])\u001f\(.e[2])\u001f\(.e[1])\u001f\(.e[3])\u001e") | add),
        bwd: ($g | map("\(.f)\u001f\(.e[1])\u001f\(.e[3])\u001f\(.e[0])\u001f\(.e[2])\u001e") | add)})) as $by
  | [$l[] | select(has("h")) | {h, p} + ($by[.k | tostring] // {f: [], fwd: "", bwd: ""})]'

# PROVE_SCOPE_JQ, over the commits ($c), the pairs known not to descend ($no,
# "older newer" -> true) and the park's reverts ($park, commit -> revert):
# newest first, a commit is taken by the nearest later commit that is still
# standing, has taken nothing yet and is its mirror image; a taken commit takes
# nothing, so an undo that is itself undone clears nothing. A pair is taken as
# descending unless $no says otherwise: the caller checks each pair in .pairs
# with git once and runs this again while a check fails. The undoing commit is
# not judged when its original carries a trailer. Cleared pairs are listed as
# found, the undoing commit's entry before its original's, then the commits a
# park's revert cleared. Only plans of the current milestone are judged and listed.
# shellcheck disable=SC2016 # a jq program
PROVE_SCOPE_JQ='$c[0] as $c | $no[0] as $no | $park[0] as $park | $rec[0] as $r
  | reduce range(0; $c | length) as $i ({pool: {}, taken: {}, took: {}, pairs: [], cleared: []};
      $c[$i] as $x
      | if $x.fwd == "" then . else
          .took as $took
          | (first((.pool[$x.fwd] // []) | reverse[] | select(($took[tostring] // 0) == 0 and ($no["\($x.h) \($c[.].h)"] | not))) // null) as $j
          | if $j == null then .pool[$x.bwd] += [$i]
            else
              .taken[$i | tostring] = true
              | .took[$j | tostring] = (if $x.p != "" then 2 else 1 end)
              | .pairs += [[$x.h, $c[$j].h]]
              | .cleared += (if $c[$j].p != "" and $x.p != "" then [{commit: $c[$j].h, plan: $c[$j].p, by: $x.h}] else [] end)
                  + (if $x.p != "" then [{commit: $x.h, plan: $x.p, by: $c[$j].h}] else [] end)
            end
        end)
  | .taken as $taken | .took as $took
  | [$c[range(0; $c | length) | select($c[.].p != "" and ($taken[tostring] | not) and ($took[tostring] // 0) != 2)]] as $judge
  | ([$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $now
  | ($r.plans | map(select(.phase as $p | $now | index($p) != null)) | map({key: .id, value: .files}) | from_entries) as $files
  | ($r.plans | map(.id as $i | {key: $i, value: ($r | survivor_files($i))}) | from_entries) as $own
  | {pairs,
     scope: [$judge[] | select($park[.h] == null and $files[.p] != null) | .h[0:12] as $h | .p as $p | .f[]
       | select(. as $f | (any($files[$p][]; covers($f)) or ($own[$p] | index($f) != null)) | not)
       | "\($h) (\($p)) changed \(.), which is not in the plan"],
     undone: ([.cleared[], ($judge[] | select($park[.h] != null) | {commit: .h, plan: .p, by: $park[.h]})] | map(select($files[.plan] != null)))}'

# prove_scope RECORD: {scope: the violations, undone: the cleared commits [{commit, plan, by}]}.
# The walk stops at the oldest commit with a VBW-Plan trailer: nothing older can be judged or
# clear one that is, so a long history from before VBW costs one plain listing.
prove_scope() {
  local dir r sha n hi hj more known=' '
  # shellcheck source=cmd-commit.sh
  . "$VBW_LIB/cmd-commit.sh"
  mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
  dir=$(mktemp -d "$VBW_RUNTIME/scope.XXXXXX") || vbw_die "cannot create a temporary folder in $VBW_RUNTIME"
  vbw_guard_add dir "$dir"
  # The commits a park undid: their changes are gone and the park recorded why, so a later plan that
  # took their plan id is not blamed for them (T163). The first revert naming a commit is its by.
  : > "$dir/park"
  while IFS= read -r r; do
    while IFS= read -r sha; do
      [ -z "$sha" ] || printf '%s %s\n' "$sha" "$r" >> "$dir/park"
    done < <(git log -1 --format=%B "$r" 2> /dev/null | sed -n 's/^This reverts commit \([0-9a-f]\{40\}\)\..*/\1/p')
  done < <(printf '%s' "$1" | jq -r '(.loop.items // [])[].reverts[]?')
  jq -R -s -c 'reduce (split("\n")[] | select(length > 0) | split(" ")) as $p ({}; if has($p[0]) then . else .[$p[0]] = $p[1] end)' "$dir/park" > "$dir/park.json"
  # How far back the first commit with a trailer lies, in the same order as the walk below.
  n=$(git log -z --topo-order --format='%x1f%(trailers:key=VBW-Plan,valueonly)' 2> /dev/null \
    | jq -R -s 'split("\u0000") | map(ltrimstr("\n") | ltrimstr("\u001f") != "") | (rindex(true) // -1) + 1') || n=0
  if [ "${n:-0}" -gt 0 ]; then
    git log -z --topo-order --no-renames --raw --no-abbrev --max-count="$n" --format='%H%x1f%(trailers:key=VBW-Plan,valueonly)' > "$dir/log" 2> /dev/null || : > "$dir/log"
  else
    : > "$dir/log"
  fi
  jq -R -s -c "$PROVE_SCOPE_PARSE_JQ" "$dir/log" > "$dir/commits" || { vbw_guard_drop "$dir"; vbw_die "internal error: the scope check could not read the history"; }
  printf '{}' > "$dir/no"
  : > "$dir/nolist"
  while :; do
    jq -n -c --slurpfile c "$dir/commits" --slurpfile no "$dir/no" --slurpfile park "$dir/park.json" --slurpfile rec <(printf '%s' "$1") \
      "$VBW_JQ_DEFS$COMMIT_SURVIVOR_DEFS$PROVE_SCOPE_JQ" > "$dir/out" || { vbw_guard_drop "$dir"; vbw_die "internal error: the scope check failed"; }
    # Each pair is checked once: does the undoing commit descend from its original?
    more=0
    while IFS=' ' read -r hi hj; do
      case "$known" in *" $hi:$hj "*) continue ;; esac
      known="$known$hi:$hj "
      git merge-base --is-ancestor "$hi" "$hj" 2> /dev/null && continue
      printf '%s %s\n' "$hi" "$hj" >> "$dir/nolist"
      more=1
    done < <(jq -r '.pairs[] | "\(.[0]) \(.[1])"' "$dir/out")
    [ "$more" = 1 ] || break
    jq -R -s -c 'split("\n") | map(select(length > 0) | {key: ., value: true}) | from_entries' "$dir/nolist" > "$dir/no"
  done
  jq -c '{scope, undone}' "$dir/out"
  vbw_guard_drop "$dir"
}

# One screen: what ran, what it means, what is next. $1: the causes that ran everything, one per line.
prove_summary() {
  jq -r --rawfile causes <(printf '%s' "$1") --arg own "$(jq -c '.evidence' "$VBW_RECORD" | prooftime_lines)" --argjson d "$VBW_COMMAND_TIMEOUT" '(.settings.command_timeout // $d) as $limit | .evidence as $e
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
      (($e.undone // [])[] | "  scope: \(.commit[0:12]) (\(.plan)) undone by \(.by[0:12]), not judged"),
      (.requirements[] | select(.proof == "auto") | "\(.id) \(.status)"),
      (.fixes[] | select(.status == "open" or .status == "escalated") | "\(.id) \(.status) (\(.req // .command), attempts \(.attempts)): \(.note)"),
      $own,
      (if $e.passed then "proved" else "not proved" end)' "$VBW_RECORD"
  jq -e '.evidence.passed' "$VBW_RECORD" > /dev/null
}
