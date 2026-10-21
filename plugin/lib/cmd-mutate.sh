#!/usr/bin/env bash
# vbw mutate (docs/proof.md): the mutation check of one rule or one task. A Dev
# breaks the plan's own code on purpose, then:
#   vbw mutate PLAN Rn.k WHAT FILE...                 rule k of requirement Rn
#   vbw mutate PLAN Rn.k --queue WHAT FILE...         the same, queued to run side by side (mutate-queue.sh)
#   vbw mutate PLAN --run                             every queued break of PLAN, side by side
#   vbw mutate PLAN taskK [--check ID]... WHAT FILE...   task K of the plan
#   vbw mutate PLAN taskK --none REASON               nothing to break in task K
# The broken bytes are set aside and the files go back to HEAD at once; the
# target's checks run in a proof copy of HEAD, unbroken and then broken. The
# result is recorded under the plan (.plans[].mutations), which the contract
# does not hold. A break no check notices is a survivor: exit 1.

# shellcheck source=checks.sh
. "$VBW_LIB/checks.sh"
# shellcheck source=cmd-commit.sh
. "$VBW_LIB/cmd-commit.sh"
# shellcheck source=proofcopy.sh
. "$VBW_LIB/proofcopy.sh"
# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"
# shellcheck source=mutate-queue.sh
. "$VBW_LIB/mutate-queue.sh"

# mutate_usage: the forms, as the message of a refusal that names the next step.
mutate_usage() {
  vbw_die "$1
usage: vbw mutate PLAN Rn.k [--queue] WHAT FILE... | PLAN --run | PLAN taskK [--check ID]... WHAT FILE... | PLAN taskK --none REASON | PLAN Rn.k --none REASON"
}

# mutate_put DIR DEST FILE...: DEST (a copy of HEAD) gets the broken bytes of each
# FILE from DIR, or loses it where the break deleted it.
mutate_put() {
  local dir="$1" dest="$2" f
  shift 2
  for f in "$@"; do
    rm -rf "${dest:?}/$f"
    if [ -e "$dir/files/$f" ] || [ -L "$dir/files/$f" ]; then
      mkdir -p "$dest/$(dirname "$f")"
      cp -pP "$dir/files/$f" "$dest/$f"
    fi
  done
  # Newer than every file in the copy, so a build that decides by file times remakes it.
  vbw_stamp_newer "$dest" "$@"
}

# mutate_clean DEST FILE...: the files back to their last commit in DEST (removed when HEAD has none).
mutate_clean() {
  local dest="$1" f
  shift
  for f in "$@"; do
    rm -rf "${dest:?}/$f"
    if git cat-file -e "HEAD:$f" 2> /dev/null; then
      git archive HEAD -- "$f" | tar -x -C "$dest" || vbw_die "cannot restore $f in the proof copy"
    fi
  done
  # Newer than the broken build, so the next unbroken run rebuilds the clean code.
  vbw_stamp_newer "$dest" "$@"
}

# mutate_rule_none PLAN REQ K RULEDOC CHECK RECORD REASON: vbw mutate PLAN Rn.k --none REASON
# (R203). The rule's check is judged by its last recorded run in the clone's run
# store, used only while current (proofreuse_current, a failed run too). With no
# run, or a stale one, the check runs once in a clean copy of the committed code
# with read tracking on and that run is stored as vbw prove would store it. The
# command never judges a list it did not record and never derives one from file names.
mutate_rule_none() {
  local plan="$1" req="$2" rk="$3" ruledoc="$4" check="$5" record="$6" reason="$7"
  local head tree fp noreads res verdict
  head=$(git rev-parse HEAD 2> /dev/null) || vbw_die "the project has no commit yet"
  checks_begin "$record"
  PROOFREUSE_STORE=$(proofreuse_store_read)
  tree=$(vbw_head_tree) || vbw_die "cannot fingerprint the committed code"
  fp=$(proofreuse_check_fp "$record" "$check")
  if proofreuse_current "check:$check" "$fp" "$tree" > /dev/null; then
    :
  else
    noreads=$(reads_probe "$VBW_RUNTIME" 2>&1) || true
    proofcopy_create_slots 1
    rm -f "$CHECK_OUT"/*.res "$CHECK_OUT"/*.res.tmp
    res=$(checks_run_all "$record" "$check")
    proofcopy_remove
    res=$(printf '%s' "$res" | jq -c --argjson off "$([ -n "$noreads" ] && echo true || echo false)" "$PROVE_FLAT")
    proofreuse_save "$record" "$res" '{}' "$tree" "$(vbw_now)"
    printf 'ran %s once to record its read list\n' "$check"
    PROOFREUSE_STORE=$(proofreuse_store_read)
  fi
  checks_end
  # The judgement: the run's read list against the files of every plan of the requirement, done or not.
  verdict=$(printf '%s' "$record" | jq -c --arg q "$req" --arg k "$req.$rk" --arg id "$check" --slurpfile st <(printf '%s' "$PROOFREUSE_STORE") '
    def fcov($f): . as $x | $x == $f or $x == "*" or (($x | endswith("/")) and ($f | startswith($x)));
    def dcov($d): . as $x | $x == $d or $x == "*" or $x == ($d + "/")
      or (($x | endswith("/")) and (($d + "/") | startswith($x)))
      or ((if ($x | test("/")) then ($x | sub("/[^/]*$"; "")) else "." end) == $d);
    def plural($n; $w): "\($n) \($w)" + (if $n == 1 then "" else "s" end);
    $st[0].runs["check:" + $id] as $e
    | [.plans[] | select(.reqs | index($q) != null)] as $pl
    | ($pl | map(select(.files | index("*") != null) | .id)) as $stars
    | if $e == null then {refuse: "\($k): \($id) has no recorded run: it did not run (vbw show contract lists check files waiting for approval)"}
      elif ($e.reads | type) != "array" then {refuse: "\($k): \($id) has no read list: the file system recorded none"}
      elif $e.git == true then {refuse: "\($k): \($id) reads the project through git, so its files are unknown: break the rule in the plan'"'"'s code instead"}
      else
        $e.reads as $rd
        | [($e.dirs // [])[] | if type == "object" then .path else . end] as $dr
        | [$rd[] as $f | {n: $f, p: [$pl[] | select(any(.files[]; fcov($f))) | .id]} | select(.p | length > 0)] as $fh
        | [$dr[] as $d | {n: $d, p: [$pl[] | select(any(.files[]; dcov($d))) | .id]} | select(.p | length > 0)] as $dh
        | def item: (.p - $stars) as $o | select($o | length > 0) | "\(.n) (\($o | join(", ")))";
          if ($fh | length) + ($dh | length) > 0 then
            ([$fh[] | item]) as $fi | ([$dh[] | item]) as $di
            | {refuse: ("\($k) is a rule its plans'"'"' code could break: \($id)"
                + (if ($fi | length) > 0 then " reads " + ($fi | join(", ")) elif ($di | length) == 0 then " reads files" else "" end)
                + (if ($di | length) > 0 then (if ($fi | length) > 0 then " and lists " else " lists " end) + ($di | join(", ")) else "" end)
                + (if ($stars | length) > 0 then "; " + ($stars | join(", ")) + (if ($stars | length) == 1 then " covers" else " cover" end) + " every file" else "" end)
                + ": break the rule in that code instead")}
          else {ok: "\($k) recorded: \($id) read \(plural($rd | length; "file")) and \(plural($dr | length; "folder")), none of them of \($q)'"'"'s plans (\($pl | map(.id) | join(", ")))"} end
      end')
  if [ "$(printf '%s' "$verdict" | jq 'has("refuse")')" = true ]; then
    vbw_die "$(printf '%s' "$verdict" | jq -r .refuse)"
  fi
  record_update '(.plans[] | select(.id == $p)).mutations += [{rule: {req: $q, text: $t}, none: $why, at: $at, head: $h}]' \
    --arg p "$plan" --arg q "$req" --arg t "$(printf '%s' "$ruledoc" | jq -r .text)" --arg why "$reason" --arg at "$(vbw_now)" --arg h "$head"
  printf '%s\n%s\n' "$(printf '%s' "$verdict" | jq -r .ok)" "$reason"
}

cmd_mutate() {
  if [ "${2:-}" = --run ]; then
    [ $# -eq 2 ] || mutate_usage "vbw mutate PLAN --run takes nothing else"
    mutate_queue_run "$1"
    return
  fi
  [ $# -ge 3 ] || mutate_usage "vbw mutate needs a plan, a rule or task, and what to break"
  local plan="$1" target="$2" kind req="" rk="" tk="" none="" nonef=0 what="" f ids i owed owns=1 ways queue=0
  shift 2
  if [[ "$target" =~ ^R([0-9]+)\.([0-9]+)$ ]]; then
    kind=rule req="R${BASH_REMATCH[1]}" rk=$((10#${BASH_REMATCH[2]}))
  elif [[ "$target" =~ ^task([0-9]+)$ ]]; then
    kind=task tk=$((10#${BASH_REMATCH[1]}))
  else
    mutate_usage "$target is neither a rule (R1.2) nor a task (task1)"
  fi
  local want=() files=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --check) [ $# -ge 2 ] || mutate_usage "--check needs a check id"; want+=("$2"); shift 2 ;;
      --none) [ $# -ge 2 ] || mutate_usage "--none needs a reason"; nonef=1 none="$2"; shift 2 ;;
      --queue) queue=1; shift ;;
      *) break ;;
    esac
  done
  { [ "$queue" = 0 ] || { [ "$kind" = rule ] && [ "$nonef" = 0 ]; }; } \
    || vbw_die "--queue is for a rule break (vbw mutate $plan Rn.k --queue WHAT FILE...): a task break and --none run at once"
  if [ "$nonef" = 1 ]; then
    if [ "$kind" = task ]; then
      [ -n "$none" ] || vbw_die "--none needs a reason: say why task $tk has no behaviour a test could notice"
    else
      [ ${#want[@]} -eq 0 ] || vbw_die "--check is for a task; a rule runs its own check"
      [ -n "$none" ] || vbw_die "--none needs a reason: say why no code the plans build could change what the check of $target judges"
    fi
    [ $# -eq 0 ] || mutate_usage "--none takes a reason and nothing else"
  else
    [ "$kind" = task ] || [ ${#want[@]} -eq 0 ] || vbw_die "--check is for a task; a rule runs its own check"
    [ $# -ge 2 ] && [ -n "$1" ] || mutate_usage "name what you broke, then the files that hold the break"
    what="$1"
    shift
    for f in "$@"; do
      f="${f#./}"
      case "$f" in "" | /* | ../* | */../* | */.. | ..) vbw_die "$f is not a path inside the project" ;; esac
      files+=("$f")
    done
  fi
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  local record
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg p "$plan" 'any(.plans[]; .id == $p)' > /dev/null || vbw_die "unknown plan $plan: vbw show roadmap lists the plans"
  local ruledoc='' check=''
  if [ "$kind" = task ]; then
    printf '%s' "$record" | jq -e --arg p "$plan" --argjson k "$tk" '.plans[] | select(.id == $p) | (.tasks // []) | length >= $k and $k >= 1' > /dev/null \
      || vbw_die "$plan has no task $tk: vbw show plan $plan lists its tasks"
  else
    printf '%s' "$record" | jq -e --arg p "$plan" --arg q "$req" '.plans[] | select(.id == $p) | .reqs | index($q) != null' > /dev/null \
      || vbw_die "$plan does not serve $req: choose a rule of a requirement it serves (vbw show plan $plan)"
    ruledoc=$(printf '%s' "$record" | jq -c --arg q "$req" --argjson k "$rk" '.requirements[] | select(.id == $q) | (.rules // []) | if $k >= 1 then (.[$k - 1] // empty | {req: $q, text, check}) else empty end')
    [ -n "$ruledoc" ] || vbw_die "$req has no rule $rk: vbw show plan $plan lists the rules, numbered"
    check=$(printf '%s' "$ruledoc" | jq -r '.check')
  fi
  if [ "$nonef" = 1 ] && [ "$kind" = rule ]; then
    mutate_rule_none "$plan" "$req" "$rk" "$ruledoc" "$check" "$record" "$none"
    return
  fi
  if [ "$nonef" = 1 ]; then
    record_update '(.plans[] | select(.id == $p)).mutations += [{task: $k, none: $why, at: $at}]' \
      --arg p "$plan" --argjson k "$tk" --arg why "$none" --arg at "$(vbw_now)"
    printf '%s recorded: nothing to break (%s)\n' "$target" "$none"
    return 0
  fi
  # The checks to run.
  if [ "$kind" = rule ]; then
    ids=$(jq -nc --arg c "$check" '[$c]')
  elif [ ${#want[@]} -gt 0 ]; then
    ids=$(printf '%s\n' "${want[@]}" | jq -R . | jq -sc 'unique')
    for i in "${want[@]}"; do
      printf '%s' "$record" | jq -e --arg p "$plan" --arg c "$i" '(.plans[] | select(.id == $p).reqs) as $q | any(.checks[]; .id == $c and ([.req] | inside($q)))' > /dev/null \
        || vbw_die "$i is not a check of the requirements $plan serves: vbw show plan $plan lists them"
    done
  else
    # The rules the plan owes: those naming it, and every rule of a requirement it completes (no other
    # open plan serves it). Their checks, each once. A plan owing no rule keeps the checks of its requirements.
    owed=$(printf '%s' "$record" | jq -c --arg p "$plan" '
      (.plans[] | select(.id == $p).reqs) as $q
      | [.plans[] | select(.id != $p and .status != "done") | .reqs[]] as $others
      | [$q[] | select(. as $r | $others | index($r) == null)] as $done
      | [.requirements[] | .id as $r | (.rules // [])[] | select(.plan == $p or ($done | index($r) != null)) | .check] | unique')
    if [ "$owed" != '[]' ]; then
      ids=$owed
    else
      owns=0
      ids=$(printf '%s' "$record" | jq -c --arg p "$plan" '(.plans[] | select(.id == $p).reqs) as $q | [.checks[] | select([.req] | inside($q)) | .id]')
    fi
  fi
  [ "$ids" != '[]' ] || vbw_die "$plan has no check to run for $target: add one with the plan's Lead, or mark the task --none"
  local idl=() cfiles=() broke=()
  while IFS= read -r i; do idl+=("$i"); done < <(printf '%s' "$ids" | jq -r '.[]')
  for f in "${files[@]}"; do
    printf '%s' "$record" | jq -e --arg p "$plan" --arg f "$f" "$VBW_JQ_DEFS"'.plans[] | select(.id == $p) | any(.files[]; . == "*" or covers($f))' > /dev/null \
      || vbw_die "$f is not one of $plan's files: break only the code the plan builds"
    printf '%s' "$record" | jq -e --arg f "$f" 'any(.checks[]; (.files // []) | index($f) != null) | not' > /dev/null \
      || vbw_die "$f is a check file: a break goes in the code under test, never in its tests"
    [ -z "$(vbw_dirty_files "$f")" ] || broke+=("$f")
  done
  [ ${#broke[@]} -gt 0 ] || vbw_die "nothing to check: none of the named files differs from the last commit; make the break in the file, then run vbw mutate"
  while IFS= read -r -d '' f; do cfiles+=("$f"); done < <(printf '%s' "$record" | jq -j --argjson ids "$ids" '[.checks[] | select(.id as $c | $ids | index($c) != null) | .files // [] | .[]] | unique[] | . + "\u0000"')
  # Also in a build run: the checks run on a copy of HEAD, so an uncommitted
  # strengthening would be tested as the old file and record a false survivor.
  if [ ${#cfiles[@]} -gt 0 ] && [ -n "$(vbw_dirty_files "${cfiles[@]}")" ]; then
    vbw_die "check files differ from the last commit: $(vbw_dirty_files "${cfiles[@]}"): commit them first, so the break is run against the approved tests"
  fi
  local head
  head=$(git rev-parse HEAD) || vbw_die "the project has no commit yet"
  checks_begin "$record"
  # The broken bytes are set aside and the files go back to HEAD, before any check starts.
  local dir
  dir=$(mktemp -d "$VBW_RUNTIME/mutate.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$dir"
  for f in "${broke[@]}"; do
    if [ -e "$f" ] || [ -L "$f" ]; then
      mkdir -p "$dir/files/$(dirname "$f")"
      cp -pP "$f" "$dir/files/$f" || vbw_die "cannot set $f aside"
    fi
    if git cat-file -e "HEAD:$f" 2> /dev/null; then
      git restore --source=HEAD --worktree -- "$f" || vbw_die "cannot restore $f to its last commit"
    else
      rm -f "$f"
    fi
  done
  # Queued (T174): the break waits, set aside, for vbw mutate PLAN --run.
  if [ "$queue" = 1 ]; then
    checks_end
    mutate_queue_add "$plan" "$dir" "$(jq -nc --arg t "$target" --arg q "$req" --argjson k "$rk" --arg c "$check" --arg w "$what" --arg h "$head" \
      --argjson files "$(printf '%s\n' "${files[@]}" | jq -R . | jq -sc .)" --argjson broke "$(printf '%s\n' "${broke[@]}" | jq -R . | jq -sc .)" \
      '{target: $t, req: $q, rk: $k, check: $c, what: $w, files: $files, broke: $broke, head: $h}')"
    return 0
  fi
  # One red check is the proof (T157): the checks run one at a time, fastest first by their last
  # recorded time (a check never run counts as slowest), until one goes red; a survivor runs them all.
  # A check runs unbroken first, unless a recorded break at this HEAD already ran it (it passed then).
  local results='{}' order base c one copy bad
  proofcopy_create_slots 1
  copy=${PROOF_COPIES[0]}
  base=$(printf '%s' "$record" | jq -c --arg p "$plan" --arg h "$head" \
    '[.plans[] | select(.id == $p) | (.mutations // [])[] | select(.head == $h) | (.checks // {}) | keys[]] | unique')
  order=$(proofreuse_store_read | jq -r --argjson ids "$ids" '.runs as $r
    | [$ids[] | {id: ., s: ($r["check:" + .].seconds // 1e9)}] | sort_by(.s, .id)[] | .id')
  for c in $order; do
    if ! printf '%s' "$base" | jq -e --arg c "$c" 'index($c) != null' > /dev/null; then
      rm -f "$CHECK_OUT"/*.res "$CHECK_OUT"/*.res.tmp
      bad=$(checks_run_all "$record" "$c" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')
      if [ -n "$bad" ]; then
        proofcopy_remove
        checks_end
        if [ "$kind" = task ]; then
          ways="ways out: make it pass and commit, then break again; or narrow the run with --check ID; or, when a later plan completes the requirement, record vbw mutate $plan task$tk --none \"REASON naming the completing plan\""
          [ "$owns" = 1 ] || ways="$plan owns no rule: the Lead names a plan on each rule, and until then every check of its requirements runs.
$ways"
          vbw_die "checks do not pass on the unbroken code, so a break proves nothing: $bad
$ways"
        fi
        vbw_die "checks do not pass on the unbroken code, so a break proves nothing: $bad; make them pass and commit, then break again"
      fi
    fi
    mutate_put "$dir" "$copy" "${broke[@]}"
    rm -f "$CHECK_OUT"/*.res "$CHECK_OUT"/*.res.tmp
    one=$(checks_run_all "$record" "$c")
    results=$(printf '%s' "$results" | jq -c --argjson o "$one" '. + $o')
    mutate_clean "$copy" "${broke[@]}"
    printf '%s' "$one" | jq -e 'all(.[]; .status == "pass")' > /dev/null || break
  done
  proofcopy_remove
  checks_end
  mutate_record "$plan" "$target" "$what" "$head" "$results" "$record" "${ruledoc:-}" "${tk:-}" \
    "$(printf '%s\n' "${files[@]}" | jq -R . | jq -sc .)" ${cfiles[@]+"${cfiles[@]}"}
}

# mutate_record PLAN TARGET WHAT HEAD RESULTS RECORD RULEDOC TASK FILES_JSON [CHECK_FILE...]:
# record one break's results (the checks it ran broken) under the plan and say
# what they show; exit 1 for a survivor. RULEDOC is the rule's {req, text, check}
# (empty for a task), TASK the task's number (empty for a rule); CHECK_WAITING is
# the files checks_begin found waiting for approval.
mutate_record() {
  local plan="$1" target="$2" what="$3" head="$4" results="$5" record="$6" ruledoc="$7" tk="$8" filesj="$9"
  shift 9
  local cfiles=("$@") f
  # What was recorded for this target before: a survivor, if the last one was.
  local prior='' strong='[]' marks result entry pending='[]' survived=0
  marks=$(printf '%s' "$results" | jq -c 'map_values(if .status == "pass" then "green" else "red" end)')
  result=red
  printf '%s' "$marks" | jq -e 'all(.[]; . == "green")' > /dev/null && result=survivor
  if [ "$result" = red ]; then
    prior=$(printf '%s' "$record" | jq -r --arg p "$plan" --argjson rule "${ruledoc:-null}" --argjson k "${tk:-0}" '.plans[] | select(.id == $p)
      | [(.mutations // [])[] | select(has("result") and (if $rule != null then .rule == {req: $rule.req, text: $rule.text} else .task == $k end))] | last
      | if . != null and .result == "survivor" then .head else empty end' 2> /dev/null) || prior=''
    if [ -n "$prior" ]; then
      strong=$(for f in ${cfiles[@]+"${cfiles[@]}"}; do git diff --quiet "$prior" HEAD -- "$f" 2> /dev/null || printf '%s\n' "$f"; done | jq -R . | jq -sc 'map(select(length > 0))')
    fi
  fi
  if [ "$result" = red ] && [ -n "${CHECK_WAITING:-}" ]; then
    # The check files that went red and wait for approval, and whether an earlier survivor of this
    # target ran that very check at another commit (so the approved version let the break through).
    pending=$(printf '%s' "$record" | jq -c --argjson marks "$marks" --arg w "$CHECK_WAITING" \
      '[.checks[] | select($marks[.id] == "red") | .files // [] | .[]] | unique | map(select(. as $f | ($w | split("\n")) | index($f) != null))')
    if [ "$pending" != '[]' ]; then
      printf '%s' "$record" | jq -e --arg p "$plan" --arg h "$head" --argjson rule "${ruledoc:-null}" --argjson k "${tk:-0}" --argjson marks "$marks" '.plans[] | select(.id == $p)
        | any((.mutations // [])[]; has("result") and .result == "survivor" and .head != $h
            and (if $rule != null then .rule == {req: $rule.req, text: $rule.text} else .task == $k end)
            and ((($marks | keys) - (.checks | keys)) | length == 0))' > /dev/null && survived=1
    fi
  fi
  entry=$(jq -nc --argjson rule "${ruledoc:-null}" --argjson k "${tk:-0}" --arg what "$what" --argjson files "$filesj" \
    --argjson marks "$marks" --arg result "$result" --arg at "$(vbw_now)" --arg head "$head" --argjson strong "$strong" --argjson pending "$pending" '
    (if $rule != null then {rule: {req: $rule.req, text: $rule.text}} else {task: $k} end)
    + {what: $what, files: $files, checks: $marks, result: $result, at: $at, head: $head}
    + (if ($strong | length) > 0 then {strengthened: $strong} else {} end)
    + (if ($pending | length) > 0 then {pending: $pending} else {} end)')
  # A survivor of a plan of the open build run opens its check files for the run (R188.33).
  record_update "$COMMIT_SURVIVOR_DEFS"'(.plans[] | select(.id == $p)).mutations += [$e]
    | if $e.result == "survivor" and .lease.kind == "build" and (.plans[] | select(.id == $p).status) == "building"
      then .lease.editable = (((.lease.editable // []) + survivor_files($p)) | unique) else . end' --arg p "$plan" --argjson e "$entry"
  if [ "$result" = survivor ]; then
    [ -z "$ruledoc" ] || what=$(printf '%s' "$ruledoc" | jq -r .text)
    printf 'survivor: %s (%s): %s still pass\n' "$target" "$what" \
      "$(printf '%s' "$marks" | jq -r 'keys | join(", ")')"
    slots_say
    return 1
  fi
  if [ "$pending" != '[]' ]; then
    local pl
    pl=$(printf '%s' "$pending" | jq -r 'join(", ")')
    if [ "$survived" = 1 ]; then
      printf '%s survives the approved check; caught by the pending one: %s\n' "$target" "$pl"
    else
      printf '%s red: %s\ncaught by a check file waiting for approval: %s\n' "$target" "$what" "$pl"
    fi
    printf '%s' "$marks" | jq -r 'to_entries[] | "\(.key) \(.value)"'
    printf 'the pending file still needs the one approval before the proof\n'
    slots_say
    return 0
  fi
  printf '%s red: %s\n' "$target" "$what"
  printf '%s' "$marks" | jq -r 'to_entries[] | "\(.key) \(.value)"'
  [ "$strong" = '[]' ] || printf 'strengthened: %s\n' "$(printf '%s' "$strong" | jq -r 'join(", ")')"
  slots_say
}
