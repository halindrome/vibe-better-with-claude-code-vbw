#!/usr/bin/env bash
# Running approved checks and commands (docs/proof.md), shared by vbw check and
# vbw prove. Nothing runs unless the current contract is approved; every argv
# is executed directly, never through a shell, with stdin closed and a timeout.

# shellcheck source=reads.sh
. "$VBW_LIB/reads.sh"

# checks_begin RECORD [strict]: die unless the contract is approved. Check
# files edited since the approval wait for it (CHECK_WAITING): the checks still
# run and the files are named, but with "strict" (proof) it dies. A check a fix
# added waits too, and never runs before the approval (CHECK_HELD, its ids).
# Sets CHECK_HASH and CHECK_OUT, a fresh output directory for this invocation
# (parallel Devs each get their own). Called directly, never in $(...).
checks_begin() {
  local waiting
  # shellcheck disable=SC2034 # read by the commands that source this file
  CHECK_HASH=$(contract_hash "$1")
  CHECK_WAITING=$(contract_waiting "$1") \
    || vbw_die "the contract is not approved, or changed since it was approved: review it (vbw show contract), then ask the user with the approval menu (AskUserQuestion)"
  if [ -n "$CHECK_WAITING" ]; then
    waiting=$(printf '%s' "$CHECK_WAITING" | tr '\n' ' ')
    [ "${2:-}" != strict ] || vbw_die "check files changed since it was approved, or added by a fix, are waiting for approval, and nothing runs them before: ${waiting% }
Next: review them, then ask the user to approve them once (vbw next asks), and run vbw prove again"
    printf 'vbw: waiting for approval (new or changed since approved): %s\n' "${waiting% }" >&2
  fi
  CHECK_HELD=$(contract_held "$1")
  CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$CHECK_OUT"
}

# Removes the output directory (also on error or interrupt, through the guard).
checks_end() {
  vbw_guard_drop "$CHECK_OUT"
}

# checks_kept check|command NAME: the file, relative to the project root, that
# keeps the complete output of the check's or project command's latest failure
# in vbw prove (R118). It lives under the git-ignored runtime folder.
checks_kept() {
  case "$1" in
    check) printf '%s/output/%s.log\n' "${VBW_RUNTIME#"$VBW_ROOT"/}" "$2" ;;
    file) printf '%s/output/file-%s.log\n' "${VBW_RUNTIME#"$VBW_ROOT"/}" "$2" ;;
    *) printf '%s/output/command-%s.log\n' "${VBW_RUNTIME#"$VBW_ROOT"/}" "$2" ;;
  esac
}

# checks_keep CHECKS COMMANDS [FILES]: the results ({name: result}) of the checks and
# project commands that just ran, their output still in CHECK_OUT. Each failure
# or timeout moves its complete output to its kept file, replacing the older
# one (renamed from a temporary file in the same folder, so a reader never sees
# half a file); a pass removes it. Reused results are not in CHECKS or COMMANDS,
# and a check or command that did not run (skipped) leaves its file as it is.
checks_keep() {
  local kind name status out kept dir tmp files=${3:-}
  [ -n "$files" ] || files='{}'
  dir="$VBW_RUNTIME/output"
  while IFS=$'\x1f' read -r -d '' kind name status; do
    case "$kind" in
      check | file) out="$CHECK_OUT/$name.out" ;;
      *) out="$CHECK_OUT/cmd-$name.out" ;;
    esac
    kept="$VBW_ROOT/$(checks_kept "$kind" "$name")"
    case "$status" in
      fail | timeout)
        [ -f "$out" ] || continue
        mkdir -p "$dir" || vbw_die "cannot create $dir"
        tmp=$(mktemp "$dir/keep.XXXXXX") || vbw_die "cannot create a temporary file in $dir"
        mv -f "$out" "$tmp" && mv -f "$tmp" "$kept" || { rm -f "$tmp"; vbw_die "cannot keep the output of $name in $kept"; }
        ;;
      pass) rm -f "$kept" ;;
    esac
  done < <(jq -n -j --slurpfile cs <(printf '%s' "$1") --slurpfile ms <(printf '%s' "$2") --slurpfile fs <(printf '%s' "$files") \
    '$cs[0] as $c | $ms[0] as $m | ($c | to_entries[] | "check\u001f\(.key)\u001f\(.value.status)\u0000"), ($m | to_entries[] | "command\u001f\(.key)\u001f\(.value.status)\u0000"),
      ($fs[0] | to_entries[] | "file\u001f\(.value.id)\u001f\(.value.status)\u0000")')
}

# checks_exec TIMEOUT OUTFILE ARGV...: run ARGV from the project root, output to
# OUTFILE, stopped at TIMEOUT seconds. Sets CHECK_CODE and CHECK_SECONDS.
checks_exec() {
  local t="$1" out="$2"
  shift 2
  SECONDS=0
  CHECK_CODE=0
  # A signal ignored by the environment stays ignored in its children (some CI
  # runners start everything with SIGALRM/SIGTERM ignored). So timeout escalates
  # to SIGKILL, which cannot be ignored, and perl resets SIGALRM before the alarm.
  # A unit never sees the session that runs the proof (VBW_SESSION_ID): a project's
  # tests must give one result whoever proves them.
  if command -v timeout > /dev/null 2>&1; then
    env -u VBW_SESSION_ID timeout -k 5 "$t" "$@" > "$out" 2>&1 < /dev/null || CHECK_CODE=$?
  else
    env -u VBW_SESSION_ID perl -e '$SIG{ALRM} = "DEFAULT"; alarm shift @ARGV; exec { $ARGV[0] } @ARGV or do { print STDERR "cannot run $ARGV[0]: $!\n"; exit 127 }' \
      "$t" "$@" > "$out" 2>&1 < /dev/null || CHECK_CODE=$?
  fi
  CHECK_SECONDS=$SECONDS
}

# checks_result OUTFILE TIMEOUT EXPECT_EXIT [OUTPUT_REGEX]: the result object.
# A run that lasted its whole timeout and failed was stopped by it. A run that
# left no output file (its wrapper died) reads as empty output.
checks_result() {
  local out="$1"
  [ -f "$out" ] || out=/dev/null
  jq -n --rawfile out "$out" --argjson code "$CHECK_CODE" --argjson secs "$CHECK_SECONDS" \
    --argjson t "$2" --argjson want "$3" --arg re "${4:-}" '
    ($out | split("\n") | map(select(length > 0)) | .[-20:] | join("\n") | .[-2000:]) as $tail
    | if $code != 0 and $secs >= $t then {status: "timeout", exit: null, seconds: $secs, tail: $tail}
      else {status: (if $code == $want and ($re == "" or ($out | test($re))) then "pass" else "fail" end),
            exit: $code, seconds: $secs, tail: $tail} end'
}

# The exclusion gate (R45), under .vbw/runtime/gate: every running check is a
# registration file "reg.PID.ID" holding "alone" or "shared". An alone check
# runs when nothing else is registered; a shared check runs when no alone check
# is registered and none is waiting. A short mutex directory makes the look and
# the registration one step. Registrations of a dead process are taken over
# (kill -0 is only a liveness probe), and every hold is released on exit,
# or interrupt through the guard. A shared check also waits while the live
# registrations already number the limit (the limit checks_run_all reads
# once per run and hands on in CHECKS_LIMIT), so separate processes never pass the limit together. The in-process
# runner starts at most the limit at once; the gate holds the same limit across
# processes. A waiting check never fails for having waited.

# checks_gate_live FILE: the process named in the file's name (NAME.PID...) is alive.
checks_gate_live() {
  local pid="${1##*/}"
  pid="${pid#*.}"
  pid="${pid%%.*}"
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null
}

# checks_gate_blocker KIND: print the check blocking KIND ("alone" or "shared")
# and return 0, or return 1 when nothing blocks. Dead registrations are dropped.
# A shared check is also blocked (printing "-") when the live registrations
# number the limit in $2 (empty: no limit).
checks_gate_blocker() {
  local kind="$1" limit="${2:-}" f id n=0
  for f in "$VBW_RUNTIME"/gate/reg.* "$VBW_RUNTIME"/gate/want.*; do
    [ -e "$f" ] || continue
    checks_gate_live "$f" || { rm -f "$f"; continue; }
    id="${f##*.}"
    case "${f##*/}" in
      want.*) [ "$kind" = shared ] || continue ;;
      *) n=$((n + 1)); [ "$kind" = alone ] || [ "$(cat "$f" 2> /dev/null)" = alone ] || continue ;;
    esac
    printf '%s\n' "$id"
    return 0
  done
  if [ "$kind" = shared ] && [ -n "$limit" ] && [ "$n" -ge "$limit" ]; then
    printf -- '-\n'
    return 0
  fi
  return 1
}

# checks_gate_enter ID ALONE: wait for the gate, then register this check.
checks_gate_enter() {
  local id="$1" kind=shared g="$VBW_RUNTIME/gate" idle=0 want='' owner limit
  [ "$2" != true ] || kind=alone
  limit="${CHECKS_LIMIT:-}"
  [ -n "$limit" ] || limit=$(vbw_check_jobs) || limit=1
  mkdir -p "$g" || vbw_die "cannot create $g"
  while :; do
    if mkdir "$g/mutex" 2> /dev/null; then
      # The lock can vanish before its owner is written (taken as stale): retry.
      { printf '%s\n' "$$" > "$g/mutex/pid"; } 2> /dev/null || { sleep 0.1; continue; }
      vbw_guard_add dir "$g/mutex"
      idle=0
      if checks_gate_blocker "$kind" "$limit" > /dev/null; then
        # An alone check that has to wait holds back new shared checks, so it is not starved.
        if [ "$kind" = alone ] && [ -z "$want" ]; then
          want="$g/want.$$.$id"
          : > "$want"
          vbw_guard_add file "$want"
        fi
      else
        [ -z "$want" ] || vbw_guard_drop "$want"
        printf '%s\n' "$kind" > "$g/reg.$$.$id"
        vbw_guard_add file "$g/reg.$$.$id"
        vbw_guard_drop "$g/mutex"
        return 0
      fi
      vbw_guard_drop "$g/mutex"
    else
      # A mutex whose owner is gone (or never wrote its pid) is taken over.
      idle=$((idle + 1))
      # The owner is read once: empty means a handover in progress, never a dead owner.
      owner=$(cat "$g/mutex/pid" 2> /dev/null)
      if [ -n "$owner" ]; then
        checks_gate_live "x.$owner" || rm -rf "$g/mutex"
      elif [ "$idle" -gt 50 ]; then
        rm -rf "$g/mutex"
      fi
    fi
    sleep 0.1
  done
}

# checks_gate_leave ID: release this check's registration.
checks_gate_leave() {
  vbw_guard_drop "$VBW_RUNTIME/gate/reg.$$.$1"
}

# The runner of units. A unit is one thing to run: a check, a project command
# or (later) a test file. It is a JSON object {name, out, argv, timeout, exit,
# output, alone}: name keys its result and its place in the gate, out is the
# file (in CHECK_OUT) that keeps its output, argv is the command, timeout the
# seconds it may take, exit and output (a regex, "" for none) what a pass is,
# alone whether nothing else may run beside it.
#
# Without slot copies (PROOF_COPIES empty) a unit runs where the caller is.
# With them (proofcopy_create_slots) each unit takes a free slot copy for its
# run, with that copy's access times reset before it and its read list
# collected after it (reads.sh); the result then carries that list as "reads"
# ({files, dirs, git}, null when it could not be written down). A copy serves
# one unit at a time, so read lists of units running together stay apart.

# checks_gate_forget NAME: drop the gate places this process holds for a unit
# whose runner is gone (killed, so it could not release them itself).
checks_gate_forget() {
  rm -f "$VBW_RUNTIME/gate/reg.$$.$1" "$VBW_RUNTIME/gate/want.$$.$1"
}

# checks_lost NAME: the result of a unit whose runner ended without leaving one.
checks_lost() {
  jq -n --arg id "$1" '{status: "skipped", exit: null, seconds: 0,
    tail: "not run: the runner of \($id) ended without a result (it was killed or crashed)"}'
}

# checks_unit RECORD ID: the unit of a check.
checks_unit() {
  printf '%s' "$1" | jq -c --arg id "$2" '.checks[] | select(.id == $id)
    | {name: .id, out: "\(.id).out", argv: .run, timeout: (.timeout // 300), exit: (.exit // 0),
       output: (.output // ""), alone: (.alone // false)}'
}

# checks_unit_run UNIT [SLOT]: run one unit, in slot copy number SLOT when
# given; print its result object.
checks_unit_run() {
  local f=() a name out t want re alone copy st="" reads=true res
  while IFS= read -r -d '' a; do f+=("$a"); done \
    < <(printf '%s' "$1" | jq -j '[.name, .out, (.timeout | tostring), (.exit | tostring), .output, (.alone | tostring)] + .argv | .[] + "\u0000"')
  name=${f[0]} out=$CHECK_OUT/${f[1]} t=${f[2]} want=${f[3]} re=${f[4]} alone=${f[5]}
  if [ -n "${2:-}" ]; then
    copy=${PROOF_COPIES[$2]}
    st="$(dirname "$copy")/reads"
    cd "$copy" || return 1
    reads_reset "$copy" "$st" || reads=false
  fi
  checks_gate_enter "$name" "$alone"
  checks_exec "$t" "$out" ${f[@]+"${f[@]:6}"}
  checks_gate_leave "$name"
  res=$(checks_result "$out" "$t" "$want" "$re")
  if [ -z "$st" ]; then
    printf '%s\n' "$res"
  elif [ "$reads" = true ] && reads_collect "$copy" "$st" > "$st/result.json"; then
    printf '%s' "$res" | jq -c --slurpfile r "$st/result.json" '. + {reads: $r[0]}'
  else
    printf '%s' "$res" | jq -c '. + {reads: null}'
  fi
}

# checks_run_units UNITS: {name: result} for the units (a JSON array), at most
# check_jobs at a time and never more than there are slot copies; a unit that
# is alone still runs by itself (the gate). Results are in the units' order.
checks_run_units() {
  local units="$1" count jobs slots cap n=0 i k pid pids=() unit name res all='{}' slot running found
  local slot_pid=() names=() j
  count=$(printf '%s' "$units" | jq 'length')
  [ "$count" -gt 0 ] || { printf '{}\n'; return 0; }
  jobs=$(vbw_check_jobs) || jobs=1
  CHECKS_LIMIT=$jobs
  slots=0
  [ -z "${PROOF_COPIES+x}" ] || slots=${#PROOF_COPIES[@]}
  cap=$jobs
  [ "$slots" -eq 0 ] || [ "$slots" -ge "$cap" ] || cap=$slots
  if [ "$cap" -le 1 ] || [ "$count" -le 1 ]; then
    slot=""
    [ "$slots" -eq 0 ] || slot=0
    for ((i = 0; i < count; i++)); do
      unit=$(printf '%s' "$units" | jq -c --argjson i "$i" '.[$i]')
      name=$(printf '%s' "$unit" | jq -r '.name')
      res=$(checks_unit_run "$unit" "$slot") || res=
      [ -n "$res" ] || { res=$(checks_lost "$name"); checks_gate_forget "$name"; }
      all=$(printf '%s' "$all" | jq -c --arg id "$name" --argjson r "$res" '. + {($id): $r}')
    done
    printf '%s\n' "$all"
    return 0
  fi
  # In parallel (bash 3.2 has no wait -n: finished jobs are counted with jobs
  # -r). Each unit runs in its own subshell, owning no guard of the parent, and
  # leaves its result in a file. A slot copy is free when its last job is gone.
  for ((i = 0; i < count; i++)); do
    unit=$(printf '%s' "$units" | jq -c --argjson i "$i" '.[$i]')
    name=$(printf '%s' "$unit" | jq -r '.name')
    slot=""
    while :; do
      running=$(jobs -r | wc -l)
      if [ "$running" -lt "$cap" ]; then
        [ "$slots" -gt 0 ] || break
        found=""
        for ((k = 0; k < slots; k++)); do
          if [ -z "${slot_pid[$k]:-}" ] || ! kill -0 "${slot_pid[$k]}" 2> /dev/null; then found=$k; break; fi
        done
        if [ -n "$found" ]; then slot=$found; break; fi
      fi
      # A runner killed without a result leaves its place in the gate: freed here.
      for ((j = 0; j < n; j++)); do
        kill -0 "${pids[$j]}" 2> /dev/null || [ -s "$CHECK_OUT/$((j + 1)).res" ] || checks_gate_forget "${names[$j]}"
      done
      sleep 0.05
    done
    n=$((n + 1))
    names+=("$name")
    (
      # The unit's own diagnostics go to its log, never to the proof's output: a
      # runner that outlives its slot (killed, its children still running) prints nowhere.
      exec 2> "$CHECK_OUT/$n.err"
      vbw_guard_reset
      res=$(checks_unit_run "$unit" "$slot") || exit 1
      printf '%s\n' "$res" > "$CHECK_OUT/$n.res.tmp" && mv "$CHECK_OUT/$n.res.tmp" "$CHECK_OUT/$n.res"
    ) &
    pid=$!
    pids+=("$pid")
    [ -z "$slot" ] || slot_pid[$slot]=$pid
    # An alone unit is at the gate before the next one starts, so a shared
    # unit launched after it never runs first.
    [ "$(printf '%s' "$unit" | jq -r '.alone')" != true ] || while kill -0 "$pid" 2> /dev/null && [ ! -e "$VBW_RUNTIME/gate/reg.$$.$name" ] && [ ! -e "$VBW_RUNTIME/gate/want.$$.$name" ]; do sleep 0.05; done
  done
  # Job notices (Killed, not a child) are the shell's own: silenced here.
  for pid in "${pids[@]}"; do { wait "$pid" || true; } 2> /dev/null; done
  for ((i = 0; i < count; i++)); do
    name=$(printf '%s' "$units" | jq -r --argjson i "$i" '.[$i].name')
    [ -s "$CHECK_OUT/$((i + 1)).res" ] || { checks_lost "$name" > "$CHECK_OUT/$((i + 1)).res"; checks_gate_forget "$name"; }
    all=$(printf '%s' "$all" | jq -c --arg id "$name" --slurpfile r "$CHECK_OUT/$((i + 1)).res" '. + {($id): $r[0]}')
  done
  printf '%s\n' "$all"
}

# checks_run_all RECORD [ID...]: {C1: result, ...} for the given checks (all
# when none are given); dies on an unknown id before running anything.
checks_run_all() {
  local record="$1" id all='{}' units='[]' res
  shift
  local ids=("$@")
  if [ ${#ids[@]} -eq 0 ]; then
    while IFS= read -r id; do [ -n "$id" ] && ids+=("$id"); done < <(printf '%s' "$record" | jq -r '.checks[].id')
  fi
  [ ${#ids[@]} -gt 0 ] || { printf '{}\n'; return 0; }
  for id in "${ids[@]}"; do
    printf '%s' "$record" | jq -e --arg id "$id" 'any(.checks[]; .id == $id)' > /dev/null || vbw_die "unknown check $id"
  done
  # A check a fix added waits for the user's approval: it is reported, never run.
  for id in "${ids[@]}"; do
    if printf '%s\n' "${CHECK_HELD:-}" | grep -qx -- "$id"; then
      all=$(printf '%s' "$all" | jq -c --arg id "$id" '. + {($id): {status: "waiting", exit: null, seconds: 0,
        tail: "not run: a check a fix added waits for the user'"'"'s approval"}}')
    else
      unit=$(checks_unit "$record" "$id")
      units=$(printf '%s' "$units" | jq -c --argjson u "$unit" '. + [$u]')
    fi
  done
  res=$(checks_run_units "$units")
  # The checks' own order, the waiting ones among them.
  printf '%s' "$res" | jq -c --slurpfile w <(printf '%s' "$all") --argjson ids "$(printf '%s\n' "${ids[@]}" | jq -R . | jq -sc .)" \
    '. + $w[0] | . as $m | reduce $ids[] as $i ({}; . + {($i): $m[$i]})'
}

# checks_must_pass RECORD WHAT CHECK...: run the checks now and die with
# "WHAT: <the failing checks>" unless every one passes. No checks: nothing runs.
checks_must_pass() {
  local record="$1" what="$2" results
  shift 2
  [ $# -gt 0 ] || return 0
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  checks_begin "$record"
  results=$(checks_run_all "$record" "$@")
  checks_end
  printf '%s' "$results" | jq -e 'all(.[]; .status == "pass")' > /dev/null \
    || vbw_die "$what: $(printf '%s' "$results" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')"
}
