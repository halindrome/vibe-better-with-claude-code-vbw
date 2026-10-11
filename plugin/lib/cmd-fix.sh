#!/usr/bin/env bash
# vbw fix check FIX < CHECK: an open fix QA opened registers its regression test
# as a check of the finding's requirement (run, files and the optional exit,
# output, timeout, alone, as vbw apply takes them; the next free C id, marked
# fix: FIX). Any other fix is refused with what to do instead.
# vbw fix done ID [ID...] | retry ID (docs/proof.md). "done" is verified, not claimed:
# for a requirement's fix, none of the files it may touch has uncommitted
# changes, and the checks of every finished requirement pass now (the one reuse
# rule of vbw prove picks which run, in clean copies), so a fix cannot quietly break other work. Then, for a requirement
# proved by checks, or a project command, it awaits proof: the next vbw prove
# closes it or counts a failed attempt. For a [human] requirement no check can
# decide, so the fix closes and the requirement returns to the user for
# acceptance. `retry` reopens an escalated fix for one more attempt (the user's
# decision at the cap; a further failure escalates again). Several fixes close in
# one command: the candidate checks run once, a failing check
# fails the fixes whose files serve it (every named fix when it serves none), and a fix that cannot close is named while the
# others still close; the exit code is non-zero when any could not.

# cmd_fix_files RECORD ID: the files the fix's requirement may touch, NUL-separated.
cmd_fix_files() {
  printf '%s' "$1" | jq -j --arg f "$2" '
    [.fixes[] | select(.id == $f)][0].req as $q
    | select($q != null) | [.plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique[] | . + "\u0000"'
}

# cmd_fix_checks RECORD ID: the checks of the finished requirements the fix's files serve.
cmd_fix_checks() {
  local files=() f
  while IFS= read -r -d '' f; do files+=("$f"); done < <(cmd_fix_files "$1" "$2")
  printf '%s' "$1" | jq -r --slurpfile files \
    <(printf '%s\n' ${files[@]+"${files[@]}"} | jq -R . | jq -sc 'map(select(length > 0))') '
    $files[0] as $files | . as $r
    | [.requirements[] | .id as $q | [$r.plans[] | select(any(.reqs[]; . == $q))] as $ps
       | select(($ps | length) > 0 and all($ps[]; .status == "done")
                and any($ps[].files[]; . as $x | any($files[]; . == $x))) | $q] as $reqs
    | .checks[] | select(.req as $q | any($reqs[]; . == $q)) | .id'
}

# cmd_fix_finished_checks RECORD: the checks of every finished requirement (it
# has plans and all are done).
cmd_fix_finished_checks() {
  printf '%s' "$1" | jq -r '. as $r
    | [.requirements[] | .id as $q | [$r.plans[] | select(any(.reqs[]; . == $q))] as $ps
       | select(($ps | length) > 0 and all($ps[]; .status == "done")) | $q] as $reqs
    | .checks[] | select(.req as $q | any($reqs[]; . == $q)) | .id'
}

# cmd_fix_check FIX: the check document on stdin becomes a check of the finding's requirement.
cmd_fix_check() {
  [ $# -eq 1 ] || vbw_usage_error "usage: vbw fix check FIX < CHECK  (a JSON object: run, files and optionally exit, output, timeout, alone)"
  vbw_require_project
  local id="$1" doc record why
  doc=$(cat)
  printf '%s' "$doc" | jq -e 'type == "object" and (keys - ["run", "files", "exit", "output", "timeout", "alone"]) == []
      and (.run | type == "array") and (.files | type == "array" and length > 0)' > /dev/null 2>&1 \
    || vbw_usage_error "the check is a JSON object on stdin: run (argv array), files (the test files it runs, non-empty) and optionally exit, output, timeout, alone"
  record=$(record_read)
  why=$(printf '%s' "$record" | jq -r --arg f "$id" '[.fixes[] | select(.id == $f)][0] as $x
    | if $x == null then "unknown fix \($f)"
      elif $x.status != "open" then "\($f) is \($x.status), not open: its checks can no longer change; QA opens a new fix if the problem remains"
      elif $x.source != "qa" then "\($f) was not opened by QA: only the fix of a QA finding adds a regression test; a proof failure is fixed in the code its check already tests, and a new check goes through the plan (vbw next)"
      else empty end')
  [ -z "$why" ] || vbw_die "$why"
  local f
  while IFS= read -r f; do
    [ -f "$VBW_ROOT/$f" ] || vbw_die "$f does not exist: create the test file before registering it"
  done < <(printf '%s' "$doc" | jq -r '.files[] | strings')
  record_update "$VBW_JQ_DEFS"'[.fixes[] | select(.id == $f)][0].req as $q
    | .checks += [{id: (.checks | next_id("C")), req: $q} + $d + {fix: $f}]' --arg f "$id" --argjson d "$doc"
  jq -r --arg f "$id" '.checks[-1] | "\(.id) added to \(.req) by \($f)"' "$VBW_RECORD"
}

cmd_fix() {
  local mode="${1:-}"
  [ "$mode" != check ] || { shift; cmd_fix_check "$@"; return; }
  { [ "$mode" = "done" ] && [ $# -ge 2 ]; } || { [ "$mode" = retry ] && [ $# -eq 2 ]; } \
    || vbw_usage_error "usage: vbw fix done ID [ID...] | fix retry ID | fix check FIX < CHECK"
  shift
  vbw_require_project
  local record id
  record=$(record_read)
  if [ "$mode" = retry ]; then
    id="$1"
    printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null || vbw_die "unknown fix $id"
    # The user decides to try again after the cap: one more attempt.
    printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "escalated")' > /dev/null \
      || vbw_die "$id is not escalated"
    record_update '(.fixes[] | select(.id == $f)).status = "open"' --arg f "$id"
    printf '%s reopened for one more attempt\n' "$id"
    return 0
  fi

  # Each named fix is judged alone: unknown, not open and dirty fixes are named
  # and left out; the rest are candidates.
  local ids=() bad=0 dirty f seen=" "
  local fl=()
  for id in "$@"; do
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    if ! printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null; then
      printf 'vbw: unknown fix %s\n' "$id" >&2
      bad=1
      continue
    fi
    if ! printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "open")' > /dev/null; then
      printf 'vbw: %s is not open\n' "$id" >&2
      bad=1
      continue
    fi
    fl=()
    while IFS= read -r -d '' f; do fl+=("$f"); done < <(cmd_fix_files "$record" "$id")
    dirty=$(vbw_dirty_files ${fl[@]+"${fl[@]}"})
    if [ -n "$dirty" ]; then
      printf 'vbw: %s has uncommitted changes in: %s (commit them with vbw commit PLAN "fix(scope): ...")\n' "$id" "$dirty" >&2
      bad=1
      continue
    fi
    ids+=("$id")
  done

  # The checks of every finished requirement are the candidates; the one reuse
  # rule of vbw prove picks which run, on clean copies, and their read lists are kept.
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
  local todo=() c at results='{}' held head noreads causes fp why served='[]' tfres='{}' tfbad='' off
  if [ ${#ids[@]} -gt 0 ]; then
    for id in "${ids[@]}"; do
      served=$(printf '%s' "$served" | jq -c --slurpfile s <(cmd_fix_checks "$record" "$id" | jq -R . | jq -sc 'map(select(length > 0))') '. + $s[0] | unique')
    done
    held=$(contract_held "$record")
    cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
    mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
    noreads=$(reads_probe "$VBW_RUNTIME" 2>&1) || true
    head=$(vbw_head_tree 2> /dev/null) || head=
    # Any cause (R168) runs every candidate check, as it does in vbw prove.
    causes=$(proofcauses_find "$record" 0 "$head")
    while IFS= read -r c; do
      [ -z "$c" ] || printf 'every candidate check runs: %s\n' "$c"
    done <<< "$causes"
    PROOFREUSE_STORE=$(proofreuse_store_read)
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      if printf '%s\n' "$held" | grep -qx -- "$c"; then
        # A check a fix added waits for the user's approval: the fix closes with the approved checks.
        printf '%s waits for the user'"'"'s approval (a check %s added: %s); vbw next asks, then vbw prove runs it\n' "$c" \
          "$(printf '%s' "$record" | jq -r --arg c "$c" '.checks[] | select(.id == $c) | .fix')" \
          "$(printf '%s' "$record" | jq -r --arg c "$c" '.checks[] | select(.id == $c) | .files | join(", ")')"
        continue
      fi
      why=$causes
      if [ -z "$why" ]; then
        fp=$(proofreuse_check_fp "$record" "$c")
        why=$(proofreuse_reason "check:$c" "$fp" "$head") || true
      fi
      if [ -z "$why" ]; then
        printf '%s unchanged since its pass (%s)\n' "$c" "$(printf '%s' "$PROOFREUSE_STORE" | jq -r --arg k "check:$c" '.runs[$k].at')"
      else
        todo+=("$c")
      fi
    done < <(cmd_fix_finished_checks "$record")
  fi
  # A test command that failed as test files is re-run on its own, file by file,
  # through the approved single-file form, never as the whole test command.
  TF_TODO=()
  if [ ${#ids[@]} -gt 0 ] && testfiles_on "$record"; then
    for id in "${ids[@]}"; do
      printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .command == "test")' > /dev/null || continue
      while IFS= read -r -d '' c; do TF_TODO+=("$c"); done < <(printf '%s' "$record" | jq -j '(.evidence.test_files // {}) | to_entries[] | select(.value.status != "pass") | .key + "\u0000"')
    done
  fi
  if [ ${#todo[@]} -gt 0 ] || [ ${#TF_TODO[@]} -gt 0 ]; then
    at=$(vbw_now)
    off=false
    [ -z "$noreads" ] || off=true
    checks_begin "$record"
    c=${#todo[@]}
    [ "$c" -ge ${#TF_TODO[@]} ] || c=${#TF_TODO[@]}
    proofcopy_create_slots "$(proofcopy_slots "$c")"
    [ ${#todo[@]} -eq 0 ] || results=$(checks_run_all "$record" "${todo[@]}")
    [ ${#TF_TODO[@]} -eq 0 ] || tfres=$(testfiles_run "$record")
    proofcopy_remove
    checks_end
    results=$(printf '%s' "$results" | jq -c --argjson off "$off" "$PROVE_FLAT")
    tfres=$(printf '%s' "$tfres" | jq -c --argjson off "$off" "$PROVE_FLAT")
    proofreuse_save "$record" "$results" '{}' "$head" "$at"
    [ "$tfres" = '{}' ] || testfiles_save "$record" "$tfres" "$head" "$at"
    tfbad=$(printf '%s' "$tfres" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')
  fi

  # Each fix ends as it would alone. A failing check fails the named fixes whose
  # files serve it, or every named fix when it serves none of them.
  local closed=() failed human fixed='[]' humans='[]'
  for id in ${ids[@]+"${ids[@]}"}; do
    if [ -n "$tfbad" ] && printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .command == "test")' > /dev/null; then
      printf 'vbw: %s: these test files still do not pass: %s\n' "$id" "$tfbad" >&2
      bad=1
      continue
    fi
    failed=$(printf '%s' "$results" | jq -r --slurpfile mine <(cmd_fix_checks "$record" "$id" | jq -R . | jq -sc 'map(select(length > 0))') --argjson all "$served" \
      '$mine[0] as $mine | [to_entries[] | select(.value.status != "pass" and (.key as $k | ($mine | index($k)) or (($all | index($k)) | not))) | "\(.key) \(.value.status)"] | join(", ")')
    if [ -n "$failed" ]; then
      printf 'vbw: %s broke finished work: these checks of finished requirements do not pass: %s\n' "$id" "$failed" >&2
      bad=1
      continue
    fi
    human=$(printf '%s' "$record" | jq -r --arg f "$id" '. as $r | [.fixes[] | select(.id == $f)][0] as $x
      | any($r.requirements[]; .id == $x.req and .proof == "human")')
    if [ "$human" = true ]; then
      humans=$(printf '%s' "$humans" | jq -c --arg f "$id" '. + [$f]')
    else
      fixed=$(printf '%s' "$fixed" | jq -c --arg f "$id" '. + [$f]')
    fi
    closed+=("$id")
  done
  if [ ${#closed[@]} -gt 0 ]; then
    record_update '. as $r | (.fixes[] | select(.id as $i | $fixed | index($i))).status = "fixed"
      | (.fixes[] | select(.id as $i | $humans | index($i))).status = "closed"
      | (.requirements[] | select(.id as $q | any($r.fixes[]; (.id as $i | $humans | index($i)) and .req == $q))).status = "open"' \
      --argjson fixed "$fixed" --argjson humans "$humans"
    for id in "${closed[@]}"; do
      if printf '%s' "$humans" | jq -e --arg f "$id" 'index($f)' > /dev/null; then
        printf '%s closed: its requirement goes back to the user for acceptance\n' "$id"
      else
        printf '%s fixed: vbw prove decides\n' "$id"
      fi
    done
  fi
  return "$bad"
}
