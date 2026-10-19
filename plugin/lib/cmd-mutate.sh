#!/usr/bin/env bash
# vbw mutate (docs/proof.md): the mutation check of one rule or one task. A Dev
# breaks the plan's own code on purpose, then:
#   vbw mutate PLAN Rn.k WHAT FILE...                 rule k of requirement Rn
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

# mutate_usage: the forms, as the message of a refusal that names the next step.
mutate_usage() {
  vbw_die "$1
usage: vbw mutate PLAN Rn.k WHAT FILE... | PLAN taskK [--check ID]... WHAT FILE... | PLAN taskK --none REASON"
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
}

cmd_mutate() {
  [ $# -ge 3 ] || mutate_usage "vbw mutate needs a plan, a rule or task, and what to break"
  local plan="$1" target="$2" kind req="" rk="" tk="" none="" nonef=0 what="" f ids i owed owns=1 ways
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
      *) break ;;
    esac
  done
  if [ "$nonef" = 1 ]; then
    [ "$kind" = task ] || vbw_die "$target is a rule: a rule always has behaviour to break; break it with vbw mutate $plan $target WHAT FILE..."
    [ -n "$none" ] || vbw_die "--none needs a reason: say why task $tk has no behaviour a test could notice"
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
  # What was recorded for this target before: a survivor, if the last one was.
  local prior='' strong='[]' marks result entry
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
  entry=$(jq -nc --argjson rule "${ruledoc:-null}" --argjson k "${tk:-0}" --arg what "$what" --argjson files "$(printf '%s\n' "${files[@]}" | jq -R . | jq -sc .)" \
    --argjson marks "$marks" --arg result "$result" --arg at "$(vbw_now)" --arg head "$head" --argjson strong "$strong" '
    (if $rule != null then {rule: {req: $rule.req, text: $rule.text}} else {task: $k} end)
    + {what: $what, files: $files, checks: $marks, result: $result, at: $at, head: $head}
    + (if ($strong | length) > 0 then {strengthened: $strong} else {} end)')
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
  printf '%s red: %s\n' "$target" "$what"
  printf '%s' "$marks" | jq -r 'to_entries[] | "\(.key) \(.value)"'
  [ "$strong" = '[]' ] || printf 'strengthened: %s\n' "$(printf '%s' "$strong" | jq -r 'join(", ")')"
  slots_say
}
