#!/usr/bin/env bash
# Real-user scenarios before a release (AGENTS.md: evidence level L3). Each
# scenario sets up a project, drives the real Claude Code TUI through
# tools/l3.sh as a user would (typing, answering questions, approving), and
# then checks the outcome in the plan of record and in git, never on screen
# text. Costs model usage: about $1-3 per scenario.
#
#   tools/l3-suite.sh [SCENARIO...]     (default: all)
#
# Scenarios are independent (own project, own Claude Code session), so they run
# L3_JOBS at a time (default 4); each one's lines print together when it ends.
#
# Scenarios: greenfield, reject, resume, change, convert, balanced, docs, qafix,
# decision, debug, research, edgecase, leftover, recheck, approval, newcomer, senior, panel, steptime, road, pluginoff, tools, legacy, nolegacy, smallchange, costs, loop, plugindir. A user
# answers every question with VBW's recommendation unless the scenario says otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
l3() { bash "$ROOT/tools/l3.sh" "$@"; }
VBW="$ROOT/plugin/bin/vbw"
ALL="greenfield reject resume change convert balanced docs qafix decision debug research edgecase leftover recheck approval newcomer senior panel steptime road pluginoff tools legacy nolegacy smallchange costs loop plugindir"
RESULTS="$ROOT/tools/l3-results"
STEPS=60

say() { printf '[%s] %s\n' "$scenario" "$*"; }

# A fresh git repository for one scenario, in the system temp directory.
new_project() {
  dir=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-$scenario.XXXXXX")
  git -C "$dir" init -q
  git -C "$dir" config user.email l3@vbw.local
  git -C "$dir" config user.name "VBW L3"
  # A neutral title: the scenario's name ("reject", "leftover") read by a
  # planner as project content once led to an unrequested task.
  printf '# Demo project\n' > "$dir/README.md"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: seed"
  # Marks a VBW test session (R64): the panel plays no sound aloud here and keeps
  # its choices under its test.vbw-panel.* keys, never the user's own.
  mkdir -p "$dir/.vbw/runtime" && : > "$dir/.vbw/runtime/test-mode"
}

next_action() { (cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.action // "none"') || echo none; }
screen() { l3 screen "$scenario"; }
default_idle() { l3 wait "$scenario" 1500 > /dev/null 2>&1 || true; }

# Answer the question on screen with the first (recommended) option. A
# multi-select question needs the option ticked, then Submit.
answer_recommended() {
  if screen | grep -q 'Ready to submit'; then
    l3 keys "$scenario" Enter
  elif screen | grep -q '\[ \]'; then
    l3 keys "$scenario" Enter; sleep 1; l3 keys "$scenario" Right; sleep 2; l3 keys "$scenario" Enter
  else
    l3 keys "$scenario" Enter
  fi
}

# answer_other TEXT: move to "Type something." and type TEXT.
# Options may still be rendering: it looks for up to 5 s before it escapes the
# menu and types (which Claude Code reports to the model as an interruption).
answer_other() {
  local n="" i
  for ((i = 0; i < 10; i++)); do
    n=$(screen | grep -E '^\s*(❯ )?[0-9]+\. Type something' | grep -oE '[0-9]+' | head -1)
    [ -n "$n" ] && break
    sleep 0.5
  done
  [ -n "$n" ] || { say "no 'Type something' option on screen; escaping the menu"; l3 keys "$scenario" Escape; sleep 1; l3 type "$scenario" "$1"; return; }
  # On "Type something." the user types at once; Enter there first would
  # submit it empty and send the text as a new prompt.
  for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
  l3 type "$scenario" "$1"
}

# drive: play the user until done() or STEPS turns. A scenario may define
# on_question (return 0 when it answered) and on_idle (return 0 when it acted).
drive() {
  local turn action
  for ((turn = 1; turn <= STEPS; turn++)); do
    idle
    screen > /dev/null 2>&1 || { say "the Claude Code session is gone"; return 1; }
    done_yet && return 0
    if screen | grep -q 'Enter to select\|Ready to submit'; then
      on_question || answer_recommended
      continue
    fi
    on_idle && continue
    action=$(next_action)
    case "$action" in
      approve) l3 type "$scenario" "/vbw:approve" ;;
      *) l3 type "$scenario" "/vbw:vibe" ;;
    esac
  done
  say "gave up after $STEPS turns (next: $(next_action))"
  return 1
}

# Defaults; scenarios override what they need.
on_question() { return 1; }
on_idle() { return 1; }
shipped() { jq -e '.milestone.status == "shipped"' "$dir/.vbw/record.json" > /dev/null 2>&1; }
done_yet() { shipped; }

# check DESCRIPTION JQ: assert on the record.
check() {
  if jq -e "$2" "$dir/.vbw/record.json" > /dev/null 2>&1; then say "ok   $1"; else say "FAIL $1"; failed=1; fi
}
check_sh() {
  if (cd "$dir" && eval "$2") > /dev/null 2>&1; then say "ok   $1"; else say "FAIL $1"; failed=1; fi
}
# expect DESCRIPTION COMMAND...: assert that COMMAND succeeds (run as argv, in $dir).
expect() {
  local d="$1"; shift
  if (cd "$dir" && "$@") > /dev/null 2>&1; then say "ok   $d"; else say "FAIL $d"; failed=1; fi
}

common_checks() {
  check "milestone shipped" '.milestone.status == "shipped"'
  check "every requirement proven or accepted" 'all(.requirements[]; .status == "proven" or .status == "accepted")'
  check "no open fixes, no lease" '(all(.fixes[]; .status == "closed")) and .lease == null'
  # grep -c reads everything: grep -q would close the pipe early, and under
  # pipefail the SIGPIPE in git log fails the check.
  check_sh "plan work committed with provenance" '[ "$(git log --format=%B | grep -c "^VBW-Plan: ")" -gt 0 ]'
  check_sh "no stray changes outside .vbw/runtime" '[ -z "$(git status --porcelain -- . ":(exclude).vbw/runtime")" ]'
}

# --- Results (docs/proof.md, D2): a scenario that proves a requirement writes
# tools/l3-results/NAME.json from the record, git and the session logs, never
# from screen text. tests/l3-results.bats holds the committed file to its facts.

claude_dir() { printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# Session transcripts of the project in $dir, the main one and its subagents'.
transcripts() {
  local real enc
  real=$(cd "$dir" && pwd -P)
  enc=$(printf '%s' "$real" | sed 's/[^A-Za-z0-9]/-/g')
  find "$(claude_dir)/projects/$enc" -name '*.jsonl' 2> /dev/null
}

# Stop hooks that reported an error in the transcript: hook errors on a
# stop_hook_summary entry, or a hook that did not complete.
stop_hook_errors_transcript() {
  local f n=0 c
  while IFS= read -r f; do
    c=$(jq -s '[.[] | select(.type == "system" and .subtype == "stop_hook_summary")
      | select((.hookErrors | length) > 0)] | length' "$f" 2> /dev/null || echo 0)
    n=$((n + c))
  done < <(transcripts)
  echo "$n"
}

# Stop-hook error lines in the session's debug log (--debug-file).
stop_hook_errors_debug_log() {
  local log
  log=$(l3 debuglog "$dir")
  [ -f "$log" ] || { echo "-1"; return; }
  grep -ciE 'stop.{0,40}hook.{0,80}(error|fail)|hook.{0,40}stop.{0,80}(error|fail)' "$log" || true
}

# Session cost in USD, from the TUI's /cost.
# Read once, before the session ends (see the main loop); checks reuse it.
session_cost() { printf '%s' "${cost_usd:-}"; }
read_session_cost() {
  local out
  l3 type "$scenario" "/cost"; sleep 3
  out=$(screen)
  l3 keys "$scenario" Escape
  printf '%s' "$out" | grep -oE '\$[0-9]+\.[0-9]+' | head -1 | tr -d '$'
}

# Agent types of the subagents the building workflow ran (their .meta.json),
# one per line, sorted and unique.
build_agent_types() {
  local f
  while IFS= read -r f; do
    jq -r 'select(.workflowPhase == "Build") | .agentType' "${f%.jsonl}.meta.json" 2> /dev/null
  done < <(transcripts | grep '/subagents/') | sort -u
}

# result_write NAME FIXTURE COST PASSED FACTS_JSON NOT_TESTED_JSON
result_write() {
  mkdir -p "$RESULTS"
  jq -n --arg n "$1" --arg fx "$2" --arg cost "${3:-0}" --argjson passed "$4" \
    --argjson facts "$5" --argjson nt "$6" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{scenario: $n, fixture: $fx, cost_usd: ($cost | tonumber), evidence_level: "L3",
      at: $at, passed: $passed, facts: $facts, not_tested: $nt}' > "$RESULTS/$1.json"
  say "result written: tools/l3-results/$1.json"
}

GREET='/vbw:vibe a command-line script greet.sh: "./greet.sh Ana" prints "Hello, Ana!" and without a name prints "Hello, world!". One small milestone.'

scenario_greenfield() {
  new_project
  start=$GREET
  checks() { common_checks; }
}

scenario_reject() {
  new_project
  start="$GREET Also, the wording should feel warm and friendly; I will judge that myself."
  rejected=0
  on_question() {
    [ "$(next_action)" = accept ] && [ "$rejected" -eq 0 ] || return 1
    screen | grep -q "Something's wrong" || return 1
    rejected=1
    local n
    n=$(screen | grep -E "[0-9]+\. Something's wrong" | grep -oE '[0-9]+' | head -1)
    local i
    for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
    l3 keys "$scenario" Enter; sleep 2
    idle
    answer_other "Too plain. Add a friendly touch, like a wave emoji after the greeting."
    return 0
  }
  checks() {
    common_checks
    check "the rejection opened a fix that was worked and closed" 'any(.fixes[]; .status == "closed" and (.note | test("friendly|emoji|plain"; "i")))'
  }
}

scenario_resume() {
  new_project
  start=$GREET
  killed=0
  # Wait like the others, but come back as soon as a run is open, so the
  # session can be closed while its workflow is still working. VBW's state is
  # read every 3 s: an express build is short, and a 30 s screen wait missed it.
  idle() {
    local waited=0 last="" now steady=0
    while [ "$waited" -lt 1500 ]; do
      [ "$killed" -eq 0 ] && [ "$(next_action)" = run ] && return 0
      now=$(screen)
      if [ "$now" = "$last" ] && ! printf '%s' "$now" | grep -q 'esc to interrupt'; then
        steady=$((steady + 3))
      else
        steady=0
      fi
      last=$now
      [ "$steady" -ge 15 ] && return 0
      sleep 3
      waited=$((waited + 3))
    done
  }
  # Back in a new session, VBW asks whether the closed session is still open:
  # the user closed it, and says so.
  on_question() {
    [ "$killed" -eq 1 ] && screen | grep -q 'That session is closed' || return 1
    local n i
    n=$(screen | grep -E '[0-9]+\. That session is closed' | grep -oE '[0-9]+' | head -1)
    for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
    l3 keys "$scenario" Enter
    return 0
  }
  done_yet() {
    if [ "$killed" -eq 0 ] && [ "$(next_action)" = run ]; then
      killed=1
      say "closing Claude Code mid-run, then starting it again"
      l3 stop "$scenario"
      l3 start "$scenario" "$dir" > /dev/null
      if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
      l3 type "$scenario" "/vbw:vibe"
    fi
    shipped
  }
  checks() {
    common_checks
    check_sh "the session was really closed mid-run" "[ $killed -eq 1 ]"
  }
}

scenario_change() {
  new_project
  start=$GREET
  changed=0
  on_question() {
    [ "$changed" -eq 0 ] && [ "$(next_action)" = ship ] || return 1
    changed=1
    answer_other "Not yet: also add a --shout flag that prints the greeting in capitals."
    return 0
  }
  checks() {
    common_checks
    check "a requirement was added before shipping" '(.requirements | length) >= 2 and any(.requirements[]; .text | test("shout|capital|upper"; "i"))'
  }
}

scenario_convert() {
  new_project
  mkdir -p "$dir/.vbw-planning/phases/01-greeting"
  printf '# Greeter\n\nA tiny command-line greeter.\n' > "$dir/.vbw-planning/PROJECT.md"
  printf '# Requirements\n\n### REQ-01: ./greet.sh NAME prints "Hello, NAME!"\n**Must-have**\n\n### REQ-02: A --version flag\n**Nice-to-have**\n' > "$dir/.vbw-planning/REQUIREMENTS.md"
  printf '# State\n\n## Key Decisions\n| Decision | Date | Rationale |\n|---|---|---|\n| Plain POSIX shell | 2026-01-01 | runs everywhere |\n' > "$dir/.vbw-planning/STATE.md"
  printf 'plan\n' > "$dir/.vbw-planning/phases/01-greeting/01-01-PLAN.md"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: VBW 1 plan"
  base=$(git -C "$dir" rev-parse HEAD)
  start="/vbw:vibe"
  done_yet() { jq -e 'has("converted") and (.requirements | length) > 0 and (.plans | length) > 0' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  checks() {
    check "converted, with requirements and a plan" 'has("converted") and (.requirements | length) > 0 and (.plans | length) > 0'
    check "the VBW 1 decision was carried over" 'any(.decisions[]; .text | test("POSIX|shell"; "i"))'
    # Tracked VBW 1 files only: on a machine that still shows VBW 1's status line,
    # that status line itself adds untracked cost files to .vbw-planning/.
    check_sh "the VBW 1 folder is unchanged" "git diff --quiet $base -- .vbw-planning"
  }
}

# Balanced autonomy with QA in the background (R8): the session runs on its
# own (auto armed by /vbw:vibe), QA runs as a background workflow, and the
# session stops at accept without a Stop-hook error.
scenario_balanced() {
  new_project
  fixture="greet.sh, one auto requirement and one human requirement"
  start="$GREET Also, the wording should feel warm and friendly; I will judge that myself."
  done_yet() { [ "$(next_action)" = accept ]; }
  checks() {
    check "QA recorded on the built phase" 'any(.phases[]; .qa.result == "pass")'
    check "stopped at accept, not shipped" '.milestone.status != "shipped"'
    check "no human requirement accepted for the user" 'all(.requirements[]; .status != "accepted")'
    local te dl cost passed=true autonomy qa_bg=false stopped=none
    te=$(stop_hook_errors_transcript); dl=$(stop_hook_errors_debug_log)
    autonomy=$(cd "$dir" && "$VBW" config autonomy 2> /dev/null)
    # QA ran as a Workflow call of vbw:verifying in the session transcript.
    if transcripts | xargs cat 2> /dev/null | jq -e 'select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and .name == "Workflow" and ((.input | tostring) | test("verifying")))' > /dev/null 2>&1; then qa_bg=true; fi
    [ "$(next_action)" = accept ] && stopped=accept
    expect "no Stop-hook errors in the transcript ($te) or the debug log ($dl)" [ "$te" -eq 0 -a "$dl" -eq 0 ]
    expect "QA ran in the background (a vbw:verifying workflow)" [ "$qa_bg" = true ]
    expect "VBW's next step is accept ($stopped)" [ "$stopped" = accept ]
    [ "$failed" -eq 0 ] && [ "$te" -eq 0 ] && [ "$dl" -eq 0 ] && [ "$stopped" = accept ] && [ "$qa_bg" = true ] || passed=false
    cost=$(session_cost)
    result_write balanced "$fixture" "${cost:-0}" "$passed" \
      "$(jq -n --arg a "$autonomy" --argjson q "$qa_bg" --argjson t "$te" --argjson d "$dl" --arg s "$stopped" \
        '{autonomy: $a, qa_background: $q, stop_hook_errors_transcript: $t, stop_hook_errors_debug_log: $d, stopped_at: $s}')" \
      '["acceptance itself (the run stops at accept)","hands-off and guided autonomy","a project larger than the greet.sh fixture"]'
  }
}

# A documentation requirement (R4): the Lead marks its plan as documentation,
# the Docs agent builds it, and the approved check proves it.
scenario_docs() {
  new_project
  fixture="greet.sh already in the repo; one auto requirement: docs/USAGE.md documents it"
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > "$dir/greet.sh"
  chmod +x "$dir/greet.sh"
  git -C "$dir" add -A && git -C "$dir" commit -qm "feat: greet.sh"
  start="/vbw:vibe Documentation only, no code changes: write docs/USAGE.md for the existing greet.sh, with how to run it with a name and without one, and one example of each. One small milestone."
  checks() {
    common_checks
    local plan req agents passed=true by=none appr=false cst=none prov=false rst=none
    plan=$(jq -r 'first(.plans[] | select(.role == "docs")) | .id // empty' "$dir/.vbw/record.json" 2> /dev/null)
    req=$(jq -r --arg p "$plan" 'first(.plans[] | select(.id == $p)) | .reqs[0] // empty' "$dir/.vbw/record.json" 2> /dev/null)
    agents=$(build_agent_types | tr '\n' ' ')
    [ "$agents" = "vbw:docs " ] && by=docs
    # Only approved checks ever run: a passing result in the evidence means approved.
    cst=$(jq -r --arg r "$req" '. as $x | first($x.checks[] | select(.req == $r)) | .id as $c | $x.evidence.checks[$c].status // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    [ "$cst" = pass ] && appr=true
    rst=$(jq -r --arg r "$req" 'first(.requirements[] | select(.id == $r)) | .status // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$plan" ] && [ "$(cd "$dir" && git log --format=%B | grep -c "^VBW-Plan: $plan\$")" -gt 0 ] && prov=true
    # Each condition prints its own line, so a failed one is never silent.
    expect "docs/USAGE.md was written" [ -f "$dir/docs/USAGE.md" ]
    expect "the Docs agent built it (agents: $agents)" [ "$by" = docs ]
    expect "an approved check proves the documentation requirement (check status: $cst)" [ "$cst" = pass ]
    expect "the documentation requirement is proven, not only accepted ($rst)" [ "$rst" = proven ]
    expect "the docs plan's commits carry provenance" [ "$prov" = true ]
    [ "$failed" -eq 0 ] && [ "$by" = docs ] && [ "$appr" = true ] && [ "$cst" = pass ] && [ "$prov" = true ] && [ "$rst" = proven ] || passed=false
    result_write docs "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg b "$by" --argjson a "$appr" --arg c "$cst" --argjson p "$prov" --arg r "$rst" --arg pl "$plan" --arg ag "$agents" \
        '{built_by_agent_type: $b, check_approved: $a, check_status: $c, commit_has_provenance: $p, requirement_status: $r, docs_plan: $pl, build_agents: $ag}')" \
      '["acceptance by a person of the documentation quality","a documentation plan mixed with code plans in one wave","a project larger than the greet.sh fixture"]'
  }
}

# Every committed version of the record, oldest first, one JSON document per
# line: the history QA verdicts and fix rounds are read from (the record keeps
# only the latest verdict).
record_history() {
  local h
  while IFS= read -r h; do
    git -C "$dir" show "$h:.vbw/record.json" 2> /dev/null | jq -c .
  done < <(git -C "$dir" log --reverse --format=%H -- .vbw/record.json)
}

# QA fails a build that deviates from its plan (R5): checks cannot see the
# deviation, QA must, and the fix loop must close it. The scenario plays the
# deviation: once the build is proven it deletes a file its plan lists that no
# check names (a commit by the "user"), the way a build that skipped a task
# would look.
scenario_qafix() {
  new_project
  fixture="greet.sh plus NOTES.md (no check names it); the built NOTES.md is deleted after the build, so only QA can see the deviation"
  deviation=""
  # Guided autonomy: the session asks before each step, which is where a user
  # (and this scenario) can act between the build and QA.
  start="Use guided autonomy for this project. $GREET Also add NOTES.md with one sentence on what greet.sh is for. Nothing automated needs to test NOTES.md: a person reads it."
  seed_deviation() {
    [ -z "$deviation" ] || return 1
    case "$(next_action)" in prove | qa) ;; *) return 1 ;; esac
    local f
    f=$(jq -r '. as $r | [$r.plans[] | .files[]] | unique[]
      | select(. as $f | ([$r.checks[] | (.run + .files)[]] | any(contains($f))) | not)' "$dir/.vbw/record.json" 2> /dev/null \
      | while IFS= read -r f; do [ -f "$dir/$f" ] && { echo "$f"; break; }; done)
    [ -n "$f" ] || return 1
    git -C "$dir" rm -q -- "$f" && git -C "$dir" commit -qm "chore: drop $f" -- "$f" || return 1
    deviation="$f"
    # The user's commit changed the code: prove it again, so the evidence (and
    # the tree QA is given) is the deviating build.
    (cd "$dir" && "$VBW" prove > /dev/null 2>&1) || true
    say "seeded the deviation: $f deleted after the build"
    return 0
  }
  # Seed, then answer the question as a user would (the recommended option).
  on_question() { seed_deviation || true; return 1; }
  on_idle() { seed_deviation; }
  done_yet() { [ -n "$deviation" ] && shipped; }
  # Human requirements (NOTES.md wording) are accepted as a user would.
  checks() {
    common_checks
    local hist first note rounds=0 final=none proved=false passed=true fv=none
    hist=$(record_history)
    first=$(printf '%s\n' "$hist" | jq -sr '[.[] | .phases[]? | select(.qa != null) | .qa] | first // {} | .result // "none"')
    fv=$first
    note=$(printf '%s\n' "$hist" | jq -sr '[.[] | select(any(.phases[]?; .qa.result == "fail"))] | first // {}
      | ([.phases[]? | .qa.note // empty] + [.fixes[]? | select(.source == "qa") | .note]) | join(" ")')
    # A fix round is one fix run (the kernel commits the record after each run).
    rounds=$(git -C "$dir" log --format=%s | grep -c '^chore(vbw): record after fix-' || true)
    final=$(jq -r '[.phases[] | .qa.result // "none"] | last // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    jq -e 'all(.requirements[]; .status == "proven" or .status == "accepted")' "$dir/.vbw/record.json" > /dev/null 2>&1 && proved=true
    say "QA rounds: first verdict $fv, fix rounds $rounds, final $final"
    [ -n "$deviation" ] || { say "FAIL the deviation was never seeded"; failed=1; }
    case "$note" in *"$deviation"*) ;; *) say "FAIL the first QA note does not name the deviation"; failed=1 ;; esac
    expect "QA's first verdict was fail ($fv)" [ "$fv" = fail ]
    expect "at least one fix round ran ($rounds)" [ "$rounds" -ge 1 ]
    expect "QA's final verdict is pass ($final)" [ "$final" = pass ]
    expect "every requirement is proven or accepted" [ "$proved" = true ]
    [ "$failed" -eq 0 ] && [ "$fv" = fail ] && [ "$rounds" -ge 1 ] && [ "$final" = pass ] && [ "$proved" = true ] || { passed=false; failed=1; }
    result_write qafix "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg d "${deviation:-}" --arg fv "$fv" --arg n "$note" --argjson r "$rounds" --arg fin "$final" --argjson p "$proved" \
        '{deviation: $d, first_qa_verdict: $fv, first_qa_note: $n, fix_rounds: $r, final_qa_verdict: $fin, phase_proved: $p}')" \
      '["a deviation other than one missing file","a deviation the Dev introduces itself (the seed is played by the scenario)","the fix cap (three failed rounds) and its escalation","a project larger than the greet.sh fixture"]'
  }
}

# QA checks again only what changed (R48): a project of two independent phases is
# built and passes QA, then a commit by the "user" touches one phase's script (the
# way a fix would), and QA runs again. The kernel's own answer just before QA
# (vbw next --json, .qa) names the phase to check again, its reason and the phases
# whose pass stands; the record then shows which phases QA really checked again.
# plan_seed: a spec of two requirements and a plan of two independent phases
# (not yet approved), so the planner's phase split and tier never decide the run.
plan_seed() {
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n- R2 [auto] ./farewell.sh Ana prints "Goodbye, Ana!"; without a name it prints "Goodbye, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]\n' > test_greet.sh
  printf '[ "$(sh farewell.sh Ana)" = "Goodbye, Ana!" ] && [ "$(sh farewell.sh)" = "Goodbye, world!" ]\n' > test_farewell.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}, {"id": "P2", "title": "Farewell", "reqs": ["R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]},
              {"id": "P2.1", "phase": "P2", "title": "farewell.sh", "reqs": ["R2"], "files": ["farewell.sh"], "after": [], "tasks": ["farewell.sh prints Goodbye, NAME! or Goodbye, world! without a name"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "test_farewell.sh"], "files": ["test_farewell.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"},
              {"req": "R2", "text": "a name gets a farewell", "check": "C2"}, {"req": "R2", "text": "no name says goodbye to the world", "check": "C2"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
}
# recheck_seed: the plan above, approved.
recheck_seed() { plan_seed && "$VBW" approve > /dev/null; }

scenario_recheck() {
  new_project
  # The user agreed the spec and approved a plan of two independent phases,
  # at standard rigor (an express phase is never QA'd, M4): the planner's
  # phase split and tier, which vary run to run, never decide this scenario.
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && recheck_seed) \
    || { say "setup failed: could not seed the approved two-phase plan"; return 1; }
  fixture="greet.sh and farewell.sh, one phase each, plan approved by the user before the session; rigor standard; after QA passes, one commit changes greet.sh and QA runs again"
  seeded="" next_json="{}" qa_before="{}"
  start="/vbw:vibe"
  phase_qa() { jq -c '. as $r | [$r.phases[] | select(.milestone == $r.milestone.id) | {key: .id, value: (.qa.at // "")}] | from_entries' "$dir/.vbw/record.json"; }
  seed_change() {
    [ -z "$seeded" ] || return 1
    jq -e '. as $r | [$r.phases[] | select(.milestone == $r.milestone.id)] | length >= 2 and all(.[]; .qa.result == "pass") and $r.milestone.status != "shipped"' "$dir/.vbw/record.json" > /dev/null 2>&1 || return 1
    local f
    f=$(jq -r '. as $r | ([$r.phases[] | select(.milestone == $r.milestone.id)][0].id) as $p
      | [$r.plans[] | select(.phase == $p) | .files[] | select(endswith(".sh"))] as $mine
      | [$r.plans[] | select(.phase != $p) | .files[]] as $others
      | [$r.checks[] | .files[]] as $tests
      | [$mine[] | select(. as $x | ($others + $tests) | index($x) | not)][0] // empty' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$f" ] && [ -f "$dir/$f" ] || return 1
    qa_before=$(phase_qa)
    printf '# reviewed by the user\n' >> "$dir/$f"
    git -C "$dir" commit -qm "chore: note in $f" -- "$f" || return 1
    (cd "$dir" && "$VBW" prove > /dev/null 2>&1) || true
    # The kernel's answer before QA runs again: what it will check and what stands.
    next_json=$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -c '.qa // {}')
    seeded="$f"
    say "changed $f after QA passed; the kernel says: $next_json"
    return 0
  }
  on_question() { seed_change || true; return 1; }
  on_idle() { seed_change; }
  done_yet() {
    [ -n "$seeded" ] || return 1
    jq -e --argjson b "$qa_before" '[.phases[] | select(.id | IN($b | keys[])) | select(.qa.at != $b[.id])] | length > 0' "$dir/.vbw/record.json" > /dev/null 2>&1
  }
  checks() {
    local after rechecked kept reason predicted standing passed=true same=false named=false
    [ -n "$seeded" ] || { say "FAIL the change was never made (QA did not pass for two phases)"; failed=1; }
    after=$(phase_qa)
    rechecked=$(jq -nc --argjson a "$qa_before" --argjson z "$after" '[$z | keys[] | select($z[.] != $a[.])]')
    kept=$(jq -nc --argjson a "$qa_before" --argjson z "$after" '[$z | keys[] | select($z[.] == $a[.])]')
    predicted=$(printf '%s' "$next_json" | jq -c '(.recheck // {}) | keys')
    standing=$(printf '%s' "$next_json" | jq -c '.standing // []')
    reason=$(printf '%s' "$next_json" | jq -r '[(.recheck // {})[] | join("; ")] | join(" | ")')
    say "checked again: $rechecked, kept: $kept, reason: $reason"
    [ "$rechecked" = "$predicted" ] && [ "$kept" = "$standing" ] && same=true
    case "$reason" in *changed*) named=true ;; esac
    expect "exactly one phase was checked again" [ "$(printf '%s' "$rechecked" | jq 'length')" -eq 1 ]
    expect "at least one phase kept its pass" [ "$(printf '%s' "$kept" | jq 'length')" -ge 1 ]
    expect "the phases QA checked again are the ones the kernel named, and the kept ones the ones it said stand" [ "$same" = true ]
    expect "the reason names what changed" [ "$named" = true ]
    # The change is a commit outside any plan, so QA may rightly fail it as a
    # deviation: what matters here is that QA judged the phase again.
    expect "QA judged the re-checked phase again and recorded a verdict" jq -e --argjson r "$rechecked" 'all(.phases[] | select(.id | IN($r[])); .qa.result == "pass" or .qa.result == "fail")' .vbw/record.json
    [ "$failed" -eq 0 ] || passed=false
    result_write recheck "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg f "${seeded:-}" --argjson r "$rechecked" --argjson k "$kept" --arg why "$reason" --argjson p "$predicted" --argjson s "$standing" \
        --argjson v "$(jq -c --argjson r "$rechecked" '[.phases[] | select(.id | IN($r[])) | {(.id): .qa.result}] | add // {}' .vbw/record.json 2> /dev/null || echo '{}')" \
        '{changed_file: $f, rechecked: $r, kept: $k, reason: $why, kernel_named_recheck: $p, kernel_named_standing: $s, new_verdict: $v}')" \
      '["a fix round of the fix loop (the change is a commit played by the scenario)","a project of more than two phases or phases that build on each other","the wording of what VBW tells the user (read by a person)","a change to a phase'"'"'s tests or plan"]'
  }
}

# Approval as a choice (R61): the user agreed the spec and the plan, and starts
# /vbw:vibe. VBW shows the contract and asks "Approve contract <fingerprint>?"
# with the options Approve and Not yet; the user presses Enter on the first one
# and never types /vbw:approve. The record and git then show the contract
# approved by VBW's own hook, once, for the fingerprint the question named.
scenario_approval() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && plan_seed) \
    || { say "setup failed: could not seed the agreed spec and plan"; return 1; }
  fixture="greet.sh and farewell.sh, one phase each; spec and plan agreed with the user before the session, contract not yet approved; rigor standard"
  asked_fp="" options_shown=false pressed=false
  start="/vbw:vibe"
  # The contract's fingerprint (12 characters), from vbw show contract.
  contract_fp() { (cd "$dir" && "$VBW" show contract 2> /dev/null | sed -n '1s/^contract \([0-9a-f]*\) .*$/\1/p' | cut -c1-12); }
  approved_now() { (cd "$dir" && "$VBW" show contract 2> /dev/null | sed -n '1p' | grep -q '(approved)'); }
  on_question() {
    local s fp
    s=$(screen)
    fp=$(printf '%s' "$s" | grep -oE 'Approve contract [0-9a-f]{12}' | head -1 | grep -oE '[0-9a-f]{12}$')
    [ -n "$fp" ] || return 1
    asked_fp=$fp
    if printf '%s' "$s" | grep -q 'Approve' && printf '%s' "$s" | grep -q 'Not yet'; then options_shown=true; fi
    # The user presses Enter on the first option, Approve.
    l3 keys "$scenario" Enter
    pressed=true
    return 0
  }
  # Never type /vbw:approve: when VBW waits for approval, ask VBW again.
  on_idle() {
    [ "$(next_action)" = approve ] || return 1
    l3 type "$scenario" "/vbw:vibe"
  }
  done_yet() { [ "$pressed" = true ] && approved_now; }
  checks() {
    local passed=true now n named
    now=$(contract_fp)
    n=$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' "$dir/.vbw/record.json" 2> /dev/null || echo 0)
    named=$(jq -r '[.decisions[] | select(.text | startswith("Contract approved")) | .text] | join(" ")' "$dir/.vbw/record.json" 2> /dev/null)
    expect "the approval question named a fingerprint (${asked_fp:-none})" [ -n "$asked_fp" ]
    expect "the question showed Approve and Not yet" [ "$options_shown" = true ]
    expect "the question named the contract's fingerprint ($now)" [ "$asked_fp" = "$now" ]
    expect "the contract is approved" approved_now
    expect "exactly one 'Contract approved' decision ($n)" [ "$n" -eq 1 ]
    case "$named" in *"($asked_fp)"*) named=true ;; *) named=false ;; esac
    expect "that decision names the fingerprint the question named" [ "$named" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write approval "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg fp "${asked_fp:-}" --argjson shown "$options_shown" --argjson e "$pressed" --argjson ok "$named" --argjson n "$n" \
        '{fingerprint: $fp, choice_shown: $shown, approved_by_enter: ($e and $ok and $n == 1), decisions: $n}')" \
      '["the answer Not yet or the user'"'"'s own words","an approval after the contract changed under the question","typing /vbw:approve (covered by the kernel tests)","a project larger than the greet.sh and farewell.sh fixture"]'
  }
}

# R62: the interview asks once whether VBW may look for tools. The user answers
# yes in the real interface; the scenario stops the search at the proposed list
# (Not yet), so nothing is installed. Facts come from the record, git and the
# session logs, never screen text.
scenario_tools() {
  new_project
  fixture="greet.sh, one small milestone on an empty README project; the interview asks the tools offer; the user answers yes, then Not yet at the proposed list"
  start=$GREET
  offers=0 answered=false listed=false declined=false before_clean=""
  # Files an install would leave in the project, outside .vbw.
  install_traces() { (cd "$dir" && git status --porcelain -- . ":(exclude).vbw" | grep -v 'greet\|farewell' | grep -ciE 'skills|\.claude|\.agents|package|lock|requirements|eslint|prettier|shellcheck|\.pre-commit' || true); }
  # `npx skills add` commands Claude ran, from the session transcripts.
  install_commands() {
    local f n=0 c
    while IFS= read -r f; do
      c=$(jq -s '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
        | (.input.command // "") | select(test("skills add|npm (i|install)|pip install|brew install"))] | length' "$f" 2> /dev/null || echo 0)
      n=$((n + c))
    done < <(transcripts)
    echo "$n"
  }
  on_question() {
    local s n i
    s=$(screen)
    # Matched on its option, which the screen never wraps.
    if printf '%s' "$s" | grep -qE '[0-9]+\. Yes, look'; then
      offers=$((offers + 1))
      # "No, skip it" is the first option: the user moves to "Yes, look" and presses Enter.
      n=$(printf '%s' "$s" | grep -E '[0-9]+\. Yes' | grep -oE '[0-9]+' | head -1)
      for ((i = 1; i < ${n:-2}; i++)); do l3 keys "$scenario" Down; done
      l3 keys "$scenario" Enter
      answered=true
      sleep 3
      return 0
    fi
    if [ "$answered" = true ] && printf '%s' "$s" | grep -qE '[0-9]+\. Not yet' && ! printf '%s' "$s" | grep -qE 'Approve contract|Ship'; then
      listed=true
      # Nothing may be installed while the list waits for the answer.
      before_clean=$([ "$(install_traces)" -eq 0 ] && [ "$(install_commands)" -eq 0 ] && echo true || echo false)
      n=$(printf '%s' "$s" | grep -E '[0-9]+\. Not yet' | grep -oE '[0-9]+' | head -1)
      for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
      l3 keys "$scenario" Enter
      declined=true
      return 0
    fi
    return 1
  }
  # The stored answer, as `vbw tools --json` reports it (project.tools in the record).
  stored() { (cd "$dir" && "$VBW" tools --json 2> /dev/null); }
  done_yet() { [ "$declined" = true ]; }
  checks() {
    local passed=true ans at again=false inst
    ans=$(stored | jq -r '.answer // "none"')
    at=$(stored | jq -r '.at // ""')
    [ "$offers" -le 1 ] || again=true
    inst=$(( $(install_traces) + $(install_commands) ))
    expect "the offer was shown (${offers})" [ "$offers" -ge 1 ]
    expect "the stored answer is yes ($ans, $at)" [ "$ans" = yes ]
    expect "it was not asked again (offers seen: $offers)" [ "$again" = false ]
    expect "the proposed list was shown" [ "$listed" = true ]
    expect "nothing was installed before the list was approved" [ "$before_clean" = true ]
    expect "nothing was installed after Not yet ($inst)" [ "$inst" -eq 0 ]
    [ "$failed" -eq 0 ] || passed=false
    result_write tools "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg a "$ans" --argjson again "$again" --argjson b "$([ "$before_clean" = true ] && echo false || echo true)" --argjson l "$listed" \
        '{answer: $a, asked_again: $again, installed_before_approval: $b, list_shown: $l}')" \
      '["the answer no","approving the list and the install itself","the question in a second session or worktree (covered by the store tests)","a project with a real stack: the fixture is one shell script"]'
  }
}

# The old VBW 1 folder (R65): the interview reviews it right after the level
# answer, recommends converting or starting fresh with the recommended option
# first, and asks once. `legacy`: the user picks the option that is NOT
# recommended (Start fresh); nothing is converted and the folder is untouched.
# `nolegacy`: a project without a folder is never asked. Facts come from the
# record, git and the session transcript, never screen text.

# Every question of the main session, in order, one JSON object per line:
# {question, options: [label...]}.
asked_questions() {
  local t
  t=$(transcripts | grep -v '/subagents/' | sort)
  [ -n "$t" ] || return 0
  printf '%s\n' "$t" | xargs cat 2> /dev/null | jq -c 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and .name == "AskUserQuestion") | .input.questions[]?
    | {question: .question, options: [.options[]?.label]}' 2> /dev/null
}

# The old-folder question: the one whose options offer Convert and Start fresh.
is_legacy_question='(.options | map(test("^Convert"; "i")) | any) and (.options | map(test("fresh"; "i")) | any)'

# Plays the interview as a user who accepts VBW's first option everywhere,
# except that the old-folder question gets Start fresh (the second option).
legacy_user() {
  purpose_done=0 followups=0 unmatched=0
  on_question() {
    local scr
    scr=$(current_question)
    if printf '%s' "$scr" | grep -qiE '[0-9]+\. Start fresh'; then
      pick_label 'Start fresh'
    elif printf '%s' "$scr" | grep -qiE 'proficiency|how should I explain|how involved|private on this machine|Ready to submit'; then
      return 1
    elif [ "$(interview_pending)" = none ]; then
      return 1
    elif [ "$purpose_done" -eq 0 ]; then
      purpose_done=1; answer_other "a little greeting tool for my grandmother, who is learning English."
    else
      followups=$((followups + 1)); answer_other "greet.sh with a name says Hello and the name, like Hello, Ana!; on its own it says Hello, world!. Nothing more."
    fi
  }
  on_idle() {
    [ "$(interview_pending)" = keep ] || return 1
    if [ "$purpose_done" -eq 0 ]; then
      last_reply | grep -qiE 'building|for whom|who.*(for|use)' || return 1
      purpose_done=1
      l3 type "$scenario" "a little greeting tool for my grandmother, who is learning English."
    else
      last_reply | grep -q '?' || return 1
      followups=$((followups + 1))
      l3 type "$scenario" "greet.sh with a name says Hello and the name, like Hello, Ana!; on its own it says Hello, world!. Nothing more."
    fi
  }
  done_yet() { (cd "$dir" && "$VBW" interview --json 2> /dev/null | jq -e '.interviewed == true and .kept != null') > /dev/null 2>&1; }
}

scenario_legacy() {
  new_project
  fixture="greet.sh from scratch; a VBW 1 folder with one finished plan whose files exist; the user picks Start fresh, the option that is not recommended"
  start="/vbw:vibe I want to build a small greeting tool. One small milestone."
  mkdir -p "$dir/.vbw-planning/phases/01-greeting"
  printf '# Greeter\n\nA tiny command-line greeter.\n' > "$dir/.vbw-planning/PROJECT.md"
  printf '# State\n\nPhase 1 done.\n' > "$dir/.vbw-planning/STATE.md"
  printf -- '---\nphase: 1\nplan: 1\nfiles_modified:\n  - README.md\n---\n# Plan\n' > "$dir/.vbw-planning/phases/01-greeting/01-01-PLAN.md"
  printf '# Summary\n\nDone.\n' > "$dir/.vbw-planning/phases/01-greeting/01-01-SUMMARY.md"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: VBW 1 plan"
  base=$(git -C "$dir" rev-parse HEAD)
  legacy_user
  checks() {
    local passed=true rec chosen conv=false first=false before=false completed=false same=false again=false n lq files new
    rec=$(cd "$dir" && "$VBW" legacy review 2> /dev/null | jq -r '.recommendation // "none"')
    chosen=$(jq -r '.project.legacy.choice // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    jq -e 'has("converted")' "$dir/.vbw/record.json" > /dev/null 2>&1 && conv=true
    [ "$(transcripts | grep -v '/subagents/' | xargs cat 2> /dev/null | jq -s '[.[] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and ((.input | tostring) | test("vbw:convert|legacy done")))] | length')" -gt 0 ] && conv=true
    lq=$(asked_questions | jq -c "select($is_legacy_question)")
    n=$(printf '%s\n' "$lq" | grep -c . || true)
    [ "$n" -le 1 ] || again=true
    printf '%s\n' "$lq" | head -1 | jq -e '(.options[0] | test("^Convert"; "i") and test("Recommended"; "i")) and (.options[1] | test("fresh"; "i"))' > /dev/null 2>&1 && first=true
    # The old-folder question comes after the level question and before every other one.
    asked_questions | jq -s -e "(map(.question | test(\"proficiency\"; \"i\")) | index(true)) as \$l
      | (map($is_legacy_question) | index(true)) as \$g
      | (map(.question | test(\"explain things|how involved|building|private\"; \"i\")) | index(true)) as \$o
      | \$l != null and \$g != null and \$l < \$g and (\$o == null or \$g < \$o)" > /dev/null 2>&1 && before=true
    done_yet && completed=true
    (cd "$dir" && git diff --quiet "$base" -- .vbw-planning && [ -z "$(git status --porcelain -- .vbw-planning)" ]) && same=true
    expect "the review recommended converting ($rec)" [ "$rec" = convert ]
    expect "the question came after the level answer and before any other" [ "$before" = true ]
    expect "the recommended option (Convert) was first, Start fresh second" [ "$first" = true ]
    expect "the user's choice was recorded as fresh ($chosen)" [ "$chosen" = fresh ]
    expect "nothing was converted" [ "$conv" = false ]
    expect "the VBW 1 folder is unchanged" [ "$same" = true ]
    expect "it was asked once ($n)" [ "$again" = false ]
    expect "the interview was completed" [ "$completed" = true ]
    # A second session asks neither the old-folder question again nor changes the choice.
    files=$(transcripts | sort)
    l3 start "$scenario" "$dir" > /dev/null
    if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
    l3 type "$scenario" "/vbw:vibe Also let greet.sh take --shout, printing the greeting in capital letters."
    default_idle
    l3 keys "$scenario" Escape; sleep 2; default_idle
    l3 stop "$scenario"
    new=$(comm -13 <(printf '%s\n' "$files") <(transcripts | sort) | grep -v '/subagents/' || true)
    if [ -n "$new" ] && printf '%s\n' "$new" | xargs cat 2> /dev/null | jq -e 'select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and .name == "AskUserQuestion") | .input.questions[]?
      | select(.options | map(.label) | map(test("fresh"; "i")) | any)' > /dev/null 2>&1; then again=true; fi
    [ "$(jq -r '.project.legacy.choice // "none"' "$dir/.vbw/record.json" 2> /dev/null)" = fresh ] || again=true
    expect "a second session did not ask again" [ "$again" = false ]
    [ "$failed" -eq 0 ] || passed=false
    result_write legacy "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg r "$rec" --arg c "$chosen" --argjson b "$before" --argjson f "$first" --argjson cv "$conv" --argjson s "$same" --argjson a "$again" --argjson ic "$completed" \
        '{recommendation: $r, choice: $c, review_before_other_questions: $b, recommended_option_first: $f, converted: $cv, old_folder_unchanged: $s, asked_again: $a, interview_completed: $ic}')" \
      '["the choice Convert and the conversion itself","a folder the review recommends starting fresh for","a real VBW 1 project: the fixture has one phase and one plan","how the review reads at each level and depth (R41, human)"]'
  }
}

scenario_nolegacy() {
  new_project
  fixture="greet.sh from scratch; a project without a VBW 1 folder; the interview is answered with VBW's first options"
  start="/vbw:vibe I want to build a small greeting tool. One small milestone."
  legacy_user
  checks() {
    local passed=true asked=false completed=false none=false
    asked_questions | jq -e "select($is_legacy_question)" > /dev/null 2>&1 && asked=true
    [ "$(cd "$dir" && "$VBW" legacy review 2> /dev/null | jq -r '.legacy')" = false ] && none=true
    [ "$(jq -r '.project.legacy // "none"' "$dir/.vbw/record.json" 2> /dev/null)" = none ] || asked=true
    done_yet && completed=true
    expect "the project has no VBW 1 folder (review says legacy false)" [ "$none" = true ]
    expect "no old-folder question was asked" [ "$asked" = false ]
    expect "the interview was completed" [ "$completed" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write nolegacy "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson a "$asked" --argjson c "$completed" '{asked_legacy: $a, interview_completed: $c}')" \
      '["a project with a leftover folder that is not a VBW 1 plan","a second session","how the interview reads (R41, human)"]'
  }
}

# The VBW panel (R51, R53, R55, R58): the real app in a wide window (200 columns, the
# panel opens by itself from 144 up) on a project with two phases, one passed and one
# whose plan waits for the user's approval. The panel is read from the screen, as the
# user sees it: the milestone, the progress, what VBW is doing, what it needs from the
# user, the cost line, and an estimate or the plain "no basis yet" (a new clone has no
# finished steps). Then the user turns the sound off, closes the panel, and starts the
# app again: the panel stays closed and the sound stays off. The one place the screen is
# the evidence is the panel itself: what it shows is what the requirement asks for.
panel_seed() {
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n- R2 [auto] ./farewell.sh Ana prints "Goodbye, Ana!"; without a name it prints "Goodbye, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]\n' > test_greet.sh
  printf '[ "$(sh farewell.sh Ana)" = "Goodbye, Ana!" ] && [ "$(sh farewell.sh)" = "Goodbye, world!" ]\n' > test_farewell.sh
  git add -A && git commit -qm "feat: greet.sh and its test" || return 1
  panel_apply "farewell.sh prints Goodbye, NAME! or Goodbye, world! without a name" || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  # The user approved the plan and the first phase was built and checked earlier;
  # the second phase's plan was then reworded and waits for approval again.
  "$VBW" approve > /dev/null && { "$VBW" prove > /dev/null 2>&1 || true; } && "$VBW" qa record P1 pass standard > /dev/null || return 1
  panel_apply "farewell.sh says Goodbye, NAME! (or Goodbye, world! with no name) and exits 0" || return 1
  # Applying a plan starts the phases over: phase 1's verdict is recorded again.
  "$VBW" qa record P1 pass standard > /dev/null || return 1
  # A What's next recommendation with rows (T160): Mission Control once opened empty
  # in the real window when the Now tab drew rows, and nothing else caught it.
  printf '%s' '{"top": {"text": "Refunds for paid orders", "reason": "Customers ask for it most this month.", "size": "small"}, "runners": [{"text": "Gift cards", "size": "large"}, {"text": "Dark mode", "size": "medium"}]}' \
    | "$VBW" recommend > /dev/null || return 1
}

# panel_apply TASK: apply the two-phase plan, P2.1 with the task TASK.
panel_apply() {
  jq -n --arg t "$1" '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}, {"id": "P2", "title": "Farewell", "reqs": ["R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]},
              {"id": "P2.1", "phase": "P2", "title": "farewell.sh", "reqs": ["R2"], "files": ["farewell.sh"], "after": ["P1.1"], "tasks": [$t]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "test_farewell.sh"], "files": ["test_farewell.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"},
              {"req": "R2", "text": "a name gets a farewell", "check": "C2"}, {"req": "R2", "text": "no name says goodbye to the world", "check": "C2"}]}' \
    | "$VBW" apply > /dev/null
}

scenario_panel() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && panel_seed) \
    || { say "setup failed: could not seed the two-phase project"; return 1; }
  fixture="greet.sh and farewell.sh, two phases: the first passed QA and its requirement R1 is proven, the second plan waits for the user's approval; no finished steps in the clone (so no estimate basis); window 200 columns wide, resized to 200x24 and to 60x40 with the needs-you line up and again while the build's helpers work; the user then approves and the build runs"
  start="/vbw:panel"
  facts="{}"
  panel_text() { screen | sed 's/[[:space:]][[:space:]]*/ /g'; }
  # The panel's text once it shows every phrase given (it redraws within seconds);
  # whatever is there after 40 s otherwise.
  panel_wait() {
    local i s p all
    for ((i = 0; i < 40; i++)); do
      s=$(panel_text) all=1
      for p in "$@"; do case "$s" in *"$p"*) ;; *) all=0 ;; esac; done
      [ "$all" -eq 1 ] && break
      sleep 1
    done
    printf '%s' "$s"
  }
  has() { case "$1" in *"$2"*) echo true ;; *) echo false ;; esac; }
  # The panel's close button is the last column of the first row.
  close_panel() { l3 click "$scenario" "$(($(tmux display -p -t "vbw-l3-$scenario" '#{window_width}') - 1))" 1; }
  observe() {
    local s mid snd
    # The panel opens by itself in a wide window; if not, the user opens it with /vbw-panel.
    if [ "$(has "$(panel_wait "Working on")" "Working on")" = false ]; then l3 type "$scenario" "/vbw-panel"; fi
    mid=$(jq -r '.milestone.id' "$dir/.vbw/record.json")
    s=$(panel_wait "Working on $mid:" "1 of 2 requirements done" "Please approve the plan" "Refunds for paid orders")
    printf '%s\n' "$s" > "$dir.panel.screen.txt"
    facts=$(jq -n --arg m "$(has "$s" "Working on $mid:")" --arg p "$(has "$s" "1 of 2 requirements done")" \
      --arg d "$(has "$s" "VBW is idle")" --arg n "$(has "$s" "Please approve the plan")" \
      --arg t "$(has "$s" "Now")$(has "$s" "Plan")$(has "$s" "Proof")$(has "$s" "Timeline")" --arg r "$(has "$s" "Refunds for paid orders")" \
      --arg c "$(case "$s" in *"has cost \$"*|*"cost so far is not available"*) echo true ;; *) echo false ;; esac)" \
      --arg e "$(case "$s" in *"No estimate yet"*) echo "no basis yet" ;; *"min left"*) echo "approximate time" ;; *) echo "" ;; esac)" \
      '{milestone_shown: ($m == "true"), progress_shown: ($p == "true"), doing_shown: ($d == "true"), need_shown: ($n == "true"),
        tabs_shown: ($t == "truetruetruetrue"), next_row_shown: ($r == "true"),
        need_text: (if $n == "true" then "Please approve the plan before VBW builds it." else "" end), cost_shown: ($c == "true"), estimate_shown: $e}')
    # The sound switch, as the user types it; the panel's own line follows within seconds.
    l3 type "$scenario" "/vbw-sound off"
    snd=$(panel_wait "Sound is off.")
    facts=$(jq -c --arg s "$(has "$snd" "Sound is off.")" '. + {sound_shown_off: ($s == "true")}' <<< "$facts")
    comms
  }
  # R189: Comms in the real window. Resize the window, wait for the redraw, and
  # read what is drawn: the prompt box must still be whole (two borders of the full
  # width and its text line on screen) and Comms must still be there, once.
  # Echoes "ok" or what was wrong. $1 columns, $2 rows, $3 the text Comms must show
  # exactly once (none: Mission Control fills the window and the pane's bottom edge must show).
  fits_window() {
    local sess="vbw-l3-$scenario" s border line
    tmux resize-window -t "$sess" -x "$1" -y "$2" 2> /dev/null || { echo "could not resize"; return; }
    sleep 8
    s=$(tmux capture-pane -t "$sess" -p)
    printf '%s\n' "$s" > "$dir.panel.$1x$2.last.txt"
    line=$(printf '─%.0s' $(seq 1 "$1"))
    border=$(printf '%s\n' "$s" | grep -cxF "$line")
    [ "$border" -ge 2 ] || { echo "the prompt box is not whole at $1x$2 ($border full-width borders)"; return; }
    printf '%s\n' "$s" | grep -q '❯' || { echo "no prompt line at $1x$2"; return; }
    if [ -n "$3" ]; then
      [ "$(printf '%s\n' "$s" | grep -cF "$3")" -eq 1 ] || { echo "'$3' is not drawn exactly once at $1x$2"; return; }
    else
      printf '%s\n' "$s" | grep -q '^╰.*╯$' || { echo "Mission Control's bottom edge is not on screen at $1x$2"; return; }
    fi
    printf '%s\n' "$s" > "$dir.panel.$1x$2.screen.txt"
    echo ok
  }
  # Both windows in turn, then the first size back. Echoes "short narrow" as true/false.
  spill_checks() {
    local a b
    a=$(fits_window 200 "$SHORT_ROWS" "$1")
    b=$(fits_window "$NARROW_COLUMNS" 40 "")
    tmux resize-window -t "vbw-l3-$scenario" -x 200 -y 60 2> /dev/null; sleep 6
    [ "$a" = ok ] || say "short window: $a" >&2
    [ "$b" = ok ] || say "narrow window: $b" >&2
    echo "$([ "$a" = ok ] && echo true || echo false) $([ "$b" = ok ] && echo true || echo false)"
  }
  SHORT_ROWS=24 NARROW_COLUMNS=60
  # The helper rows of Comms (the left 120 columns, under the "VBW ▸" line): "role label" per row.
  crew_rows() {
    screen | cut -c1-120 | awk '/VBW ▸/ { on = 1; next } on && /^─/ { on = 0 } on' \
      | grep -oE '(^|[[:space:]])(architect|lead|dev|qa|scout|debugger|docs) {2,}[^ ]+' | sed 's/^[[:space:]]*//; s/  */ /g'
  }
  comms() {
    local shown cleared=false pair sh nr i s
    # 1. The needs-you line stands while the plan waits for approval.
    s=$(panel_wait "⚑ VBW needs you")
    shown=$(has "$s" "⚑ VBW needs you")
    pair=$(spill_checks "⚑ VBW needs you")
    sh=${pair% *} nr=${pair#* }
    # 2. The user approves; the line must go once the gate is answered.
    l3 type "$scenario" "/vbw:approve"
    for ((i = 0; i < 40; i++)); do
      sleep 3
      if screen | grep -q 'Enter to select\|Ready to submit'; then answer_recommended; continue; fi
      if ! screen | grep -q "VBW needs you" && [ "$(next_action)" != approve ]; then cleared=true; break; fi
    done
    # 3. The build: helpers come and go on Comms. A row seen once, then gone while the
    # top line counts "N done", is a finished helper that left. The window is also
    # resized once while helpers are at work.
    local seen_rows="" cur r started=false done_gone=false how="" crew_sh=true crew_nr=true crew_checked=false act
    local waiting=0
    for ((i = 0; i < 400; i++)); do
      sleep 3
      if screen | grep -q 'Enter to select\|Ready to submit'; then answer_recommended; continue; fi
      act=$(next_action)
      # Claude Code goes on to the build by itself after an approval; if it has not within 45 s, the user asks.
      if [ "$started" = false ] && [ "$act" = build ] && ! screen | grep -q 'esc to interrupt'; then
        waiting=$((waiting + 1))
        if [ "$waiting" -ge 15 ]; then l3 type "$scenario" "/vbw:vibe"; waiting=0; fi
      fi
      cur=$(crew_rows)
      screen > "$dir.panel.build.last.txt"
      if [ -n "$cur" ]; then
        started=true
        while IFS= read -r r; do case "$seen_rows" in *"|$r|"*) ;; *) seen_rows="$seen_rows|$r|" ;; esac; done <<< "$cur"
        if [ "$crew_checked" = false ]; then
          crew_checked=true
          pair=$(spill_checks "VBW ▸")
          crew_sh=${pair% *} crew_nr=${pair#* }
          continue
        fi
      fi
      if [ -n "$seen_rows" ] && [ "$done_gone" = false ] && screen | cut -c1-120 | grep -qE 'VBW ▸.* [1-9][0-9]* done'; then
        while IFS= read -r r; do
          [ -n "$r" ] || continue
          case "$cur" in *"$r"*) ;; *) done_gone=true how="a helper's row left while the top line counted it done" ;; esac
        done <<< "$(printf '%s' "$seen_rows" | sed 's/^|//; s/|$//; s/||/\
/g')"
      fi
      if [ "$started" = true ] && [ "$act" != build ] && [ "$act" != run ]; then
        if [ "$done_gone" = false ] && ! screen | cut -c1-120 | grep -q 'VBW ▸'; then done_gone=true how="the run ended and the crew left Comms"; fi
        break
      fi
    done
    facts=$(jq -c --arg sh "$shown" --argjson cl "$cleared" --argjson dg "$done_gone" --arg how "$how" --argjson st "$started" \
      --argjson s1 "$sh" --argjson n1 "$nr" --argjson s2 "$crew_sh" --argjson n2 "$crew_nr" \
      --argjson sr "$SHORT_ROWS" --argjson nc "$NARROW_COLUMNS" \
      '. + {need_line_shown: ($sh == "true"), need_line_cleared: $cl, helper_seen_working: $st, helper_done_cleared: $dg, helper_done_how: $how,
            no_spill_short: ($s1 and $s2), no_spill_narrow: ($n1 and $n2), short_rows: $sr, narrow_columns: $nc}' <<< "$facts")
  }
  done_yet() { observe; return 0; }
  checks() {
    local snd_back before
    # The first session's panel: close it as a person does, then start the app again.
    l3 start "$scenario" "$dir" > /dev/null
    if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
    panel_wait "Working on" > /dev/null
    close_panel
    sleep 5
    before=$(has "$(panel_text)" "Working on")
    l3 stop "$scenario"
    l3 start "$scenario" "$dir" > /dev/null
    if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
    sleep 10
    # Closed by the user: still closed after the restart. The sound was turned off: the switch says it is back on.
    l3 type "$scenario" "/vbw-sound"; sleep 4
    snd_back=$(panel_text)
    facts=$(jq -c --arg b "$before" --arg c "$(has "$snd_back" "Working on")" --arg o "$(has "$snd_back" "sound is on")" \
      '. + {closed_by_click: ($b == "false"), closed_stays_closed: ($b == "false" and $c == "false"), sound_toggle_persisted: ($o == "true")}' <<< "$facts")
    sleep 2
    l3 stop "$scenario"
    local k passed
    for k in milestone_shown progress_shown doing_shown need_shown tabs_shown next_row_shown cost_shown sound_shown_off closed_by_click closed_stays_closed sound_toggle_persisted need_line_shown need_line_cleared helper_seen_working helper_done_cleared no_spill_short no_spill_narrow; do
      expect "the panel: $k" jq -e --arg k "$k" '.[$k] == true' <<< "$facts"
    done
    expect "the panel shows an estimate or the plain 'no basis yet'" jq -e '.estimate_shown | length > 0' <<< "$facts"
    passed=$(jq -r '[.milestone_shown, .progress_shown, .doing_shown, .need_shown, .tabs_shown, .next_row_shown, .cost_shown, .sound_shown_off, .closed_by_click, .closed_stays_closed, .sound_toggle_persisted, .need_line_shown, .need_line_cleared, .helper_seen_working, .helper_done_cleared, .no_spill_short, .no_spill_narrow, (.estimate_shown | length > 0)] | all' <<< "$facts")
    [ "$passed" = true ] || failed=1
    result_write panel "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["the sound itself (nothing was heard: the run only checks the switch)","what a person reads at a glance: wording and layout are judged on the screen text, not by a reader","no spill is read from the visible tmux screen after a resize (prompt box whole, Comms drawn once), not from a real terminal'"'"'s scrollback","one short window (200 columns, 24 rows) and one narrow window (60 columns, 40 rows), with the needs-you line and with helpers at work; no other size","Comms in the 60-column window: Mission Control fills that window and Comms'"'"' own line is not on screen there (seen in the run, not judged), so the narrow check holds the prompt box and the pane'"'"'s bottom edge only","Mission Control'"'"'s own rows and tabs at those sizes (held by tests/panel/r189/containment.test.mjs, L1)","figure counts and the motion levels (full, calm, off)","a failed helper, a celebration and a ship in the real window","a milestone shipped before the recommendation (the seed stores the recommendation on an active milestone)","a time estimate with a number"]'
  }
}

# steptime (R190, phase P148): the step's end time in the real window. A project
# with two plans and six slow real checks, no step history at first. Phase 1: the
# scenario starts a build run by hand (the kernel's own `vbw run start build`), so
# a project with no history shows the step with no end time in the status line and
# Comms, and `vbw next` says so; it ends the run. Phase 2: it seeds a history of
# three finished builds (and proofs) in the clone, the user types /vbw:vibe, and the
# build runs through the real window. Sampled every 2 s from the screen: VBW's
# message in the chat ("until around HH:MM"), the status line under the prompt
# box ("until HH:MM") and Comms (the "VBW ▸" strip: "until around HH:MM") must read
# the same time; the status line's "proving N of M checks" must count up.
steptime_seed() {
  local i
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n- R2 [auto] ./farewell.sh Ana prints "Goodbye, Ana!"; without a name it prints "Goodbye, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  # Three checks per requirement, each waits 5 s first: a proof takes long enough to watch.
  for i in 1 2 3; do
    case $i in 1) a=Ana b="Hello, Ana!" c="Goodbye, Ana!" ;; 2) a="" b="Hello, world!" c="Goodbye, world!" ;; 3) a=Bo b="Hello, Bo!" c="Goodbye, Bo!" ;; esac
    printf 'sleep 5\n[ "$(sh greet.sh %s)" = "%s" ]\n' "$a" "$b" > "test_greet_$i.sh"
    printf 'sleep 5\n[ "$(sh farewell.sh %s)" = "%s" ]\n' "$a" "$c" > "test_farewell_$i.sh"
  done
  git add -A && git commit -qm "test: the greeting checks" || return 1
  jq -n '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}, {"id": "P2", "title": "Farewell", "reqs": ["R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]},
              {"id": "P2.1", "phase": "P2", "title": "farewell.sh", "reqs": ["R2"], "files": ["farewell.sh"], "after": ["P1.1"], "tasks": ["farewell.sh prints Goodbye, NAME! or Goodbye, world! without a name"]}],
    "checks": [(range(1; 4) as $i | {"id": "C\($i)", "req": "R1", "run": ["sh", "test_greet_\($i).sh"], "files": ["test_greet_\($i).sh"]}),
               (range(1; 4) as $i | {"id": "C\($i + 3)", "req": "R2", "run": ["sh", "test_farewell_\($i).sh"], "files": ["test_farewell_\($i).sh"]})],
    "rules": [(range(1; 4) as $i | {"req": "R1", "text": "greeting case \($i)", "check": "C\($i)"}),
              (range(1; 4) as $i | {"req": "R2", "text": "farewell case \($i)", "check": "C\($i + 3)"})]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
  # Two checks at a time, so the count steps 0, 2, 4, 6 and can be seen.
  "$VBW" config set check_jobs 2 > /dev/null
}

# The history the clone would have after three earlier builds (2 plans, 10 min) and three proofs (6 checks, 1 min).
steptime_history() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir) || return 1
  mkdir -p "$common/vbw"
  jq -n '{steps: [(range(0; 3) as $i | {kind: "build", run: "build-seed-\($i)", started_at: "2026-10-15T09:00:00Z", ended_at: "2026-10-15T09:10:00Z", seconds: 600, parts: 2}),
                  (range(0; 3) as $i | {kind: "proof", run: "proof-seed-\($i)", started_at: "2026-10-15T09:10:00Z", ended_at: "2026-10-15T09:11:00Z", seconds: 60, parts: 6})]}' \
    > "$common/vbw/steps.json"
}

scenario_steptime() {
  new_project
  export L3_STATUSLINE=1
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && steptime_seed) \
    || { say "setup failed: could not seed the two-plan project"; return 1; }
  fixture="greet.sh and farewell.sh (two plans, the second after the first), six real checks that wait 5 s each (check_jobs 2), approved; the working tree's status line on, the panel in a wide window; no step history first (a build run started by the scenario with vbw run start build, then ended), then a seeded history of three builds of 2 plans in 10 min and three proofs of 6 checks in 1 min, and the user types /vbw:vibe for the real build"
  start="/vbw:status"
  st_phase=A st_nohist_status=false st_nohist_text=false st_nohist_next=false
  st_samples="$dir.steptime.samples" st_stop="$dir.steptime.stop"
  rm -f "$st_samples" "$st_stop"
  # What the three places say now: sets sw_* variables.
  st_read() {
    local s
    s=$(screen) || return 1
    sw_status=$(printf '%s\n' "$s" | awk '/^─/ { n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }')
    sw_comms=$(printf '%s\n' "$s" | sed 's/│.*//' | awk '/VBW ▸/ { on = 1 } on && /^─/ { on = 0 } on')
    sw_chat=$(printf '%s\n' "$s" | sed 's/│.*//' | awk '/^─/ { exit } /VBW ▸/ { exit } { print }')
    sw_screen=$s
  }
  st_time() { grep -oE "$1 (tomorrow )?[0-9]{2}:[0-9]{2}" | head -1 | grep -oE '[0-9]{2}:[0-9]{2}$' || true; }
  # One sample, a tab-separated line: chat time, status line time, Comms time, the status line's
  # proof count (done, total) and the note's first end in local time.
  st_sample() {
    local chat sl cm n m note
    st_read || return 1
    chat=$(printf '%s\n' "$sw_chat" | grep -iE 'building|fixing|proving|checking' | st_time 'until around')
    sl=$(printf '%s\n' "$sw_status" | st_time 'until')
    cm=$(printf '%s\n' "$sw_comms" | st_time 'until around')
    n="" m=""
    if printf '%s\n' "$sw_status" | grep -qE 'proving [0-9]+ of [0-9]+ checks'; then
      n=$(printf '%s\n' "$sw_status" | grep -oE 'proving [0-9]+ of [0-9]+ checks' | head -1 | grep -oE '[0-9]+' | sed -n 1p)
      m=$(printf '%s\n' "$sw_status" | grep -oE 'proving [0-9]+ of [0-9]+ checks' | head -1 | grep -oE '[0-9]+' | sed -n 2p)
    fi
    note=$(jq -r '(.first_end // empty) | fromdateiso8601 | localtime | strftime("%H:%M")' "$dir/.vbw/runtime/step.json" 2> /dev/null || true)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$chat" "$sl" "$cm" "$n" "$m" "$note" >> "$st_samples"
  }
  # Every 2 s until the session is gone or the stop file is there; the waits of the
  # driver (a background build keeps it idle for minutes) do not thin it out.
  st_sampler() { while [ ! -f "$st_stop" ]; do st_sample || break; sleep 2; done; }
  # Phase A: no history. The scenario starts the build run; the window shows it with no end time.
  st_no_history() {
    local i sayt
    sayt=$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.step.say // ""')
    case "$sayt" in *"no end time yet"*) st_nohist_next=true ;; esac
    (cd "$dir" && "$VBW" run start build P1.1 > /dev/null 2>&1) || { say "could not start the run by hand"; return; }
    for ((i = 0; i < 20; i++)); do
      sleep 2
      st_read
      if printf '%s\n' "$sw_status" | grep -q '▶ build' && ! printf '%s\n' "$sw_status" | grep -q 'until'; then st_nohist_status=true; fi
      case "$sw_screen" in *"No end time yet"*) st_nohist_text=true ;; esac
      [ "$st_nohist_status" = true ] && [ "$st_nohist_text" = true ] && break
    done
    printf '%s\n' "$sw_screen" > "$dir.steptime.nohistory.screen.txt"
    (cd "$dir" && "$VBW" run end > /dev/null 2>&1) || say "could not end the run started by hand"
  }
  plans_done() { jq -e '[.plans[]? | .status] | length > 0 and all(. == "done")' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  done_yet() {
    if [ "$st_phase" = A ]; then
      st_no_history
      (cd "$dir" && steptime_history) || { say "could not seed the history"; return 0; }
      say "seeded the clone's steps.json: 3 builds of 2 plans in 10 min, 3 proofs of 6 checks in 1 min"
      st_phase=B
      st_sampler &
      l3 type "$scenario" "/vbw:vibe"
      return 1
    fi
    shipped && return 0
    plans_done || return 1
    # Both plans are built: go on until the proof after them has run and been seen counting.
    case "$(next_action)" in build | run | prove) return 1 ;; esac
    awk -F'\t' '$4 != "" { found = 1 } END { exit !found }' "$st_samples" 2> /dev/null
  }
  checks() {
    : > "$st_stop"
    wait
    local counts same up passed chat sl cm note total
    chat=$(awk -F'\t' '$1 != "" { print $1; exit }' "$st_samples")
    sl=$(awk -F'\t' '$2 != "" { print $2; exit }' "$st_samples")
    cm=$(awk -F'\t' '$3 != "" { print $3; exit }' "$st_samples")
    note=$(awk -F'\t' '$6 != "" { print $6; exit }' "$st_samples")
    total=$(awk -F'\t' '$5 != "" { print $5; exit }' "$st_samples")
    # The longest run of counts that never went down, from the status line over time.
    counts=$(awk -F'\t' '$4 != "" { n = $4 + 0
        if (len > 0 && n < last) { if (len > blen) { best = seq; blen = len } seq = ""; len = 0 }
        if (len == 0 || n != last) { seq = seq (len ? " " : "") n; len++ }
        last = n }
      END { if (len > blen) best = seq; print best }' "$st_samples" | tr ' ' '\n' | jq -R 'select(length > 0) | tonumber' | jq -s .)
    same=$([ -n "$chat" ] && [ "$chat" = "$sl" ] && [ "$chat" = "$cm" ] && echo true || echo false)
    up=$(jq -n --argjson c "$counts" '($c | length) >= 2 and ($c[-1] > $c[0]) and ([range(1; $c | length) as $i | $c[$i] >= $c[$i - 1]] | all)')
    facts=$(jq -n --arg chat "$chat" --arg sl "$sl" --arg cm "$cm" --arg note "$note" --argjson same "$same" \
      --argjson counts "$counts" --argjson up "$up" --argjson total "${total:-0}" \
      --argjson nhs "$st_nohist_status" --argjson nht "$st_nohist_text" --argjson nhn "$st_nohist_next" \
      --argjson samples "$(wc -l < "$st_samples" | tr -d ' ')" \
      '{chat_end: $chat, statusline_end: $sl, comms_end: $cm, note_first_end: $note, same_end: $same,
        proof_counts: $counts, proof_total: $total, proof_counted_up: $up,
        no_history_no_end_time: ($nhs and $nht and $nhn), no_history_status_line_without_time: $nhs, no_history_screen_says_no_end_time: $nht, no_history_next_says_no_end_time: $nhn,
        screen_samples: $samples}')
    expect "chat, status line and Comms each gave an end time" jq -e '.chat_end != "" and .statusline_end != "" and .comms_end != ""' <<< "$facts"
    expect "the three end times are the same" jq -e '.same_end == true' <<< "$facts"
    expect "the three end times are the note's first end" jq -e '.note_first_end == .chat_end' <<< "$facts"
    expect "the background proof counted up" jq -e '.proof_counted_up == true' <<< "$facts"
    expect "with no history the window shows no end time" jq -e '.no_history_no_end_time == true' <<< "$facts"
    passed=$(jq -r '.chat_end != "" and .same_end and (.note_first_end == .chat_end) and .proof_counted_up and .no_history_no_end_time' <<< "$facts")
    [ "$passed" = true ] || failed=1
    result_write steptime "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a build that ran late: the end moving to this run'"'"'s pace was not seen in the window (held by tests/step-note.bats, L1)","an end time on another day","a fix, QA, planning or mapping step in the window","the three times are read from the visible screen text at 2 s steps, by the first time each place showed one, not by a reader","the project with no history had a build started by the scenario with vbw run start, not by the router, so the router saying no end time yet in chat was not seen (vbw next --json gave it)","the status line, Comms and the chat message were read in one 200-column window only","the proof counted was the one the build flow ran with check_jobs 2; its pace on a machine with more lanes","the time left shrinking, a user watching, and the clock time being right to the minute against real elapsed time"]'
  }
}

# road (R191, phase P151): the end of the milestone, the road, in the real window.
# The steptime project (two plans in two phases of one milestone, six slow real
# checks), with a history of the kind R191 reads: plan units with tiers and tasks,
# proofs with their units (and the runs store), QA phases with tiers, fix rounds
# with tiers, and the outcomes of three finished phases in an earlier, shipped
# milestone. Phase A has no history: vbw next --json says no end time yet for the
# step and for the road, a run started by hand writes the same into the note, and
# the screen shows it. Phase B seeds the history and the outcomes (the way a project
# that shipped before has them) and the user types /vbw:vibe; the build runs through
# the real window. Sampled every 2 s from the screen: VBW's message in the chat (the
# step's sentence, then "Milestone end: ... until around HH:MM"), Mission Control's
# milestone row, the status line under the prompt box (it shows the step's time
# only), and from the step note the road's end. The two milestone times must agree
# within a minute.
scenario_road() {
  new_project
  export L3_STATUSLINE=1
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && steptime_seed) \
    || { say "setup failed: could not seed the two-plan project"; return 1; }
  fixture="greet.sh and farewell.sh (two plans in two standard phases of one milestone, the second after the first), six real checks that wait 5 s each (check_jobs 2), approved; the working tree's status line on, the panel in a wide window; no history first (a build run started by the scenario with vbw run start build, then ended), then a seeded history (three builds of one plan of one task at 5 min, three proofs of the six checks, three QA checks of one phase at 2 min, three fix rounds at 200 s, the runs store with the six checks at 5 s) and three finished phases of a shipped milestone with 1, 1 and 2 fix rounds, and the user types /vbw:vibe for the real build"
  start="/vbw:status"
  road_history() {
    local common
    common=$(git rev-parse --path-format=absolute --git-common-dir) || return 1
    mkdir -p "$common/vbw"
    # Three earlier builds of one plan of one task (5 min), three proofs of the six
    # checks (5 s each, 20 s of wall time), three QA checks of one phase (2 min) and
    # three fix rounds (200 s), all at the standard tier; the runs store knows the six checks.
    jq -n '[range(1; 7) | "check:C\(.)"] as $names
      | {steps: [
        (range(0; 3) as $i | {kind: "build", run: "build-seed-\($i)", started_at: "2026-10-15T09:00:00Z", ended_at: "2026-10-15T09:05:00Z", seconds: 300, parts: 1,
           units: [{id: "P9.\($i)", tier: "standard", tasks: 1, seconds: 300}]}),
        (range(0; 3) as $i | {kind: "proof", run: "proof-seed-\($i)", started_at: "2026-10-15T09:10:00Z", ended_at: "2026-10-15T09:10:20Z", seconds: 20, parts: 6,
           units: [$names[] | {name: ., seconds: 5}]}),
        (range(0; 3) as $i | {kind: "qa", run: "qa-seed-\($i)", started_at: "2026-10-15T09:11:00Z", ended_at: "2026-10-15T09:13:00Z", seconds: 120,
           phases: [{id: "P9\($i)", tier: "standard"}]}),
        (range(0; 3) as $i | {kind: "fix", run: "fix-seed-\($i)", started_at: "2026-10-15T09:14:00Z", ended_at: "2026-10-15T09:17:20Z", seconds: 200, parts: 1,
           fixes: ["F\($i)"], tier: "standard"})]}' > "$common/vbw/steps.json"
    jq -n '[range(1; 7) | "check:C\(.)"] as $names
      | {runs: ($names | map({key: ., value: {fp: "seed", tree: "seed", status: "pass", at: "2026-10-15T09:10:00Z", seconds: 5, tail: "", reads: null, dirs: [], git: false}}) | from_entries)}' \
      > "$common/vbw/runs.json"
  }

  # Three finished phases of an earlier milestone, shipped, each at the standard tier
  # with its fix rounds (1, 1 and 2: the usual is 1), as a project that shipped before has them.
  road_outcomes() {
    local r=.vbw/record.json
    jq '.shipped = [{id: "M0", title: "Before", at: "2026-10-01T00:00:00Z"}]
      | .phases += [([1, 1, 2] | to_entries[]) as $e | {id: "P9\($e.key)", title: "Earlier phase \($e.key)", reqs: ["R1"], milestone: "M0", tier: "standard",
          qa: {result: "pass", tier: "standard", tree: "old", at: "2026-10-01T00:00:00Z"},
          outcome: {tier: "standard", predicted: "standard", held: true, fix_rounds: $e.value, qa_findings: 0, escalations: 0}}]' "$r" > "$r.tmp" \
      && mv "$r.tmp" "$r" && git add .vbw/record.json && git commit -qm "chore(vbw): earlier phases" || return 1
  }
  rd_phase=A rd_nohist_next=false rd_nohist_note=false rd_nohist_screen=false
  rd_samples="$dir.road.samples" rd_stop="$dir.road.stop"
  rm -f "$rd_samples" "$rd_stop"
  # What the places say now: sets rd_* variables (text without the panel, the panel's text, the status line).
  rd_read() {
    local s
    s=$(screen) || return 1
    # Claude Code's own "Teach auto mode about your environment?" dialog can open after
    # a turn and takes the next typed text: the user would press Esc, so the scenario does.
    case "$s" in *"Teach auto mode about your environment"*) l3 keys "$scenario" Escape; sleep 1; s=$(screen) || return 1 ;; esac
    # The seeded ship opens Mission Control on VBW Wrapped, which hides its rows until a tab
    # is chosen: the user would click Now, so the scenario does.
    case "$s" in *"VBW Wrapped"*)
      row=$(printf '%s\n' "$s" | grep -n '\[ Now \]' | head -1 | cut -d: -f1)
      pre=$(printf '%s\n' "$s" | grep '\[ Now \]' | head -1 | sed 's/\[ Now \].*//')
      if [ -n "$row" ]; then
        l3 click "$scenario" "$(($(printf '%s' "$pre" | LC_ALL=en_US.UTF-8 wc -m) + 4))" "$row"
        sleep 1; s=$(screen) || return 1
      fi ;;
    esac
    rd_status=$(printf '%s\n' "$s" | awk '/^─/ { n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }')
    rd_chat=$(printf '%s\n' "$s" | sed 's/│.*//' | awk '/^─/ { exit } /VBW ▸/ { exit } { print }' | tr '\n' ' ' | tr -s ' ')
    rd_panel=$(printf '%s\n' "$s" | sed -n 's/^[^│]*│//p' | sed 's/│//g' | tr '\n' ' ' | tr -s ' ')
    rd_screen=$s
  }
  # The first "Milestone end: ... until around HH:MM" in a text, the HH:MM.
  rd_road_time() { grep -oE 'Milestone end:[^.]*until around [0-9]{2}:[0-9]{2}' | head -1 | grep -oE '[0-9]{2}:[0-9]{2}$' || true; }
  # The chat's step time: the first "until around HH:MM" that comes before the first "Milestone end:".
  rd_step_time() {
    grep -oE 'Milestone end:|until around [0-9]{2}:[0-9]{2}' \
      | awk '/^Milestone end:/ { exit } { print; exit }' | grep -oE '[0-9]{2}:[0-9]{2}$' || true
  }
  # One sample, a tab-separated line: the chat's step time, the chat's road time, Mission Control's
  # road time, whether the status line mentions the milestone, the status line's time and the note's road end.
  rd_sample() {
    local cs cr pr sh sl nr
    rd_read || return 1
    cs=$(printf '%s\n' "$rd_chat" | rd_step_time)
    cr=$(printf '%s\n' "$rd_chat" | rd_road_time)
    pr=$(printf '%s\n' "$rd_panel" | rd_road_time)
    sh=0
    printf '%s\n' "$rd_status" | grep -qiE 'milestone end|no milestone end' && sh=1
    sl=$(printf '%s\n' "$rd_status" | grep -oE 'until (tomorrow )?[0-9]{2}:[0-9]{2}' | head -1 | grep -oE '[0-9]{2}:[0-9]{2}$' || true)
    nr=$(jq -r '(.road.end // empty) | fromdateiso8601 | localtime | strftime("%H:%M")' "$dir/.vbw/runtime/step.json" 2> /dev/null || true)
    # The screen while the build runs and the chat has the milestone's time (kept for the reader).
    case "$rd_panel" in *"Current step: building"*) printf '%s\n' "$rd_screen" > "$dir.road.building.screen.txt" ;; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$cs" "$cr" "$pr" "$sh" "$sl" "$nr" >> "$rd_samples"
  }
  rd_sampler() { while [ ! -f "$rd_stop" ]; do rd_sample || break; sleep 2; done; }
  # Phase A: no history. The scenario starts the build run; the window shows no end time.
  rd_no_history() {
    local i
    case "$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '(.step.say // "") + " | " + (.road.say // "")')" in
      *"no end time yet"*"no milestone end time yet"*) rd_nohist_next=true ;;
    esac
    (cd "$dir" && "$VBW" run start build P1.1 > /dev/null 2>&1) || { say "could not start the run by hand"; return; }
    for ((i = 0; i < 20; i++)); do
      sleep 2
      rd_read
      # Mission Control opens by itself in a wide window; if not, the user opens it with /vbw-panel.
      if [ "$i" -eq 5 ]; then case "$rd_screen" in *"[ Now ]"*) ;; *) l3 type "$scenario" "/vbw-panel" ;; esac; fi
      case "$rd_screen" in *"No estimate yet"*) rd_nohist_screen=true ;; esac
      jq -e '.road != null and .road.end == null and (.road.say | test("no milestone end time yet"))' "$dir/.vbw/runtime/step.json" > /dev/null 2>&1 && rd_nohist_note=true
      [ "$rd_nohist_screen" = true ] && [ "$rd_nohist_note" = true ] && break
    done
    printf '%s\n' "$rd_screen" > "$dir.road.nohistory.screen.txt"
    (cd "$dir" && "$VBW" run end > /dev/null 2>&1) || say "could not end the run started by hand"
  }
  plans_done() { jq -e '[.plans[]? | .status] | length > 0 and all(. == "done")' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  done_yet() {
    if [ "$rd_phase" = A ]; then
      rd_no_history
      (cd "$dir" && road_history && road_outcomes) || { say "could not seed the history"; return 0; }
      say "seeded the clone's history (builds, proofs, QA, fix rounds, runs) and three finished phases of a shipped milestone"
      rd_phase=B
      rd_sampler &
      l3 type "$scenario" "/vbw:vibe"
      return 1
    fi
    shipped && return 0
    plans_done || return 1
    case "$(next_action)" in build | run | prove) return 1 ;; esac
    awk -F'\t' '$2 != "" { a = 1 } $3 != "" { b = 1 } END { exit !(a && b) }' "$rd_samples" 2> /dev/null
  }
  checks() {
    : > "$rd_stop"
    wait
    local cs cr pr sh sl nr same
    first() { awk -F'\t' -v c="$1" '$c != "" { print $c; exit }' "$rd_samples"; }
    cs=$(first 1) cr=$(first 2) pr=$(first 3) sl=$(first 5) nr=$(first 6)
    sh=$(awk -F'\t' '$4 == 1 { f = 1 } END { print f ? "true" : "false" }' "$rd_samples")
    # Within a minute of each other (the clock wraps at midnight).
    within() { awk -v a="$1" -v b="$2" 'function m(t) { split(t, p, ":"); return p[1] * 60 + p[2] }
      BEGIN { d = m(a) - m(b); if (d < 0) d = -d; if (1440 - d < d) d = 1440 - d; exit !(d <= 1) }'; }
    same=false
    if [ -n "$cr" ] && [ -n "$pr" ] && [ -n "$nr" ] && within "$cr" "$pr" && within "$cr" "$nr" && within "$pr" "$nr"; then same=true; fi
    facts=$(jq -n --arg cs "$cs" --arg cr "$cr" --arg pr "$pr" --arg nr "$nr" --arg sl "$sl" --argjson same "$same" --argjson sh "$sh" \
      --argjson nhn "$rd_nohist_next" --argjson nht "$rd_nohist_note" --argjson nhs "$rd_nohist_screen" \
      --argjson samples "$(wc -l < "$rd_samples" | tr -d ' ')" \
      '{chat_step_end: $cs, chat_road_end: $cr, panel_road_end: $pr, note_road_end: $nr, same_road_end: $same,
        statusline_end: $sl, statusline_has_road: $sh,
        no_history_no_end_time: ($nhn and $nht and $nhs), no_history_next_says_no_end_time: $nhn, no_history_note_says_no_end_time: $nht, no_history_screen_says_no_end_time: $nhs,
        screen_samples: $samples}')
    expect "the chat gave the step's time and the milestone's" jq -e '.chat_step_end != "" and .chat_road_end != ""' <<< "$facts"
    expect "Mission Control gave the milestone's time" jq -e '.panel_road_end != ""' <<< "$facts"
    expect "chat, Mission Control and the note give the same milestone time" jq -e '.same_road_end == true' <<< "$facts"
    expect "the status line showed a time and no milestone" jq -e '.statusline_end != "" and .statusline_has_road == false' <<< "$facts"
    expect "with no history the window and vbw next show no end time" jq -e '.no_history_no_end_time == true' <<< "$facts"
    passed=$(jq -r '.chat_step_end != "" and .chat_road_end != "" and .panel_road_end != "" and .same_road_end and .statusline_end != "" and (.statusline_has_road | not) and .no_history_no_end_time' <<< "$facts")
    [ "$passed" = true ] || failed=1
    result_write road "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a build that ran late: the milestone end moving with each late plan was not seen in the window (held by tests/road-note.bats, L1)","fix rounds, QA, planning and mapping steps in the window: the road was read at the build'"'"'s start and during the proof","a milestone end on another day, and a duration over an hour","the times are read from the visible screen text at 2 s steps, by the first time each place showed one, not by a reader","the project with no history had a build run started by the scenario with vbw run start, not by the router, so the router saying both sentences in chat without history was not seen (vbw next --json and the note gave them)","the earlier phases, the history and the runs store are seeded by the scenario in the clone and the record, not made by earlier real runs","the chat, Mission Control and the status line were read in one 200-column window only","the milestone time being right to the minute against real elapsed time","Claude Code'"'"'s own Teach auto mode dialog and the VBW Wrapped card the seeded ship opens were dismissed by the scenario (Esc, a click on Now), as a user would"]'
  }
}

# pluginoff (R184): a VBW project whose own .claude/settings.json turns the VBW
# plugin off. VBW runs as the user's installed marketplace plugin (L3_MODE=installed:
# --plugin-dir may not honour enabledPlugins "vbw@vbw-marketplace"), with the
# working tree's status line on, in a window wide enough for the panel. The
# facts: Claude Code itself reports VBW off (debug log), whether it still
# loaded the panel module, and whether anything of VBW is on the screen.
scenario_pluginoff() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null \
    && printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"\n' > .vbw/spec.md \
    && "$VBW" spec sync > /dev/null \
    && mkdir -p .claude \
    && jq -n '{enabledPlugins: {"vbw@vbw-marketplace": false}}' > .claude/settings.json \
    && git add -A && git commit -qm "chore: VBW project that turns the VBW plugin off") \
    || { say "setup failed: could not seed the project"; return 1; }
  export L3_STATUSLINE=1 L3_MODE=installed
  fixture="a small VBW project (vbw init, one-requirement spec) whose .claude/settings.json sets enabledPlugins vbw@vbw-marketplace to false; VBW is the installed marketplace plugin, the session shows the working tree's status line; window 200 columns wide"
  start="Reply with the single word ok."
  seen=""
  done_yet() {
    sleep 20
    seen=$(screen | sed 's/[[:space:]][[:space:]]*/ /g')
    printf '%s\n' "$seen" > "$dir.pluginoff.screen.txt"
    return 0
  }
  checks() {
    local log off=false module=false panel=false line=false passed
    log=$(l3 debuglog "$dir")
    [ -f "$log" ] || log=/dev/null
    grep -qiE 'vbw[^ ]*.{0,80}(disabled|not enabled|is off)|(disabled|skipping).{0,80}vbw' "$log" && off=true
    grep -q 'hooks/panel\.js' "$log" && module=true
    printf '%s' "$seen" | grep -qE 'Working on|VBW is idle|VBW next:|VBW needs you|VBW building|No VBW project is open' && panel=true
    printf '%s' "$seen" | grep -qF '[VBW]' && line=true
    expect "Claude Code reports VBW turned off in the project" [ "$off" = true ]
    expect "no panel on screen" [ "$panel" = false ]
    expect "no VBW status line on screen" [ "$line" = false ]
    passed=true
    [ "$off" = true ] && [ "$panel" = false ] && [ "$line" = false ] || passed=false
    [ "$passed" = true ] || failed=1
    result_write pluginoff "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson o "$off" --argjson m "$module" --argjson p "$panel" --argjson l "$line" \
        '{plugin_disabled_confirmed: $o, panel_module_loaded: $m, panel_shown: $p, vbw_statusline_shown: $l}')" \
      '["the hand-back to an earlier status line through the installed setting (this session shows the working tree script directly)","the installed plugin version, which is not the working tree'"'"'s","user-level settings that turn VBW off (the project'"'"'s own file only)","a narrow window","a project that turns VBW off while a VBW run is live"]'
  }
}

# plugindir (R185): VBW is installed from the marketplace AND the working tree is
# loaded with claude --plugin-dir, in a session whose inherited PATH already
# holds the installed release's bin/ (a session started from inside another
# one). The session and one VBW agent it starts each run 'command -v vbw' and
# 'vbw version'. The facts come from the session transcripts and the debug log:
# which copies load, which hooks ran, the vbw each resolved, the plugin data
# folder name and CLAUDE_ENV_FILE the loaded copy's SessionStart hook gets (a
# probe hook in a throwaway copy of the tree in .vbw/runtime/scratch/, whose
# plugin.json version is suffixed when it equals the installed one, so the two
# copies tell apart). The result name comes from the caller: L3_PLUGINDIR_RESULT
# (plugindir-probe before the fix, plugindir after it; default plugindir).
# L3_PLUGINDIR_INHERIT=0 starts without the installed bin/ on PATH.
scenario_plugindir() {
  new_project
  # The caller names the result: plugindir-probe before the fix, plugindir after it.
  pd_name=${L3_PLUGINDIR_RESULT:-plugindir}
  pd_tree="$ROOT/.vbw/runtime/scratch/plugindir-tree"
  local inst_root inst_ver tree_ver
  inst_root=$(jq -r '.plugins["vbw@vbw-marketplace"][0].installPath // empty' "$(claude_dir)/plugins/installed_plugins.json" 2> /dev/null)
  [ -n "$inst_root" ] && [ -x "$inst_root/bin/vbw" ] || { say "setup failed: no installed VBW release (vbw@vbw-marketplace) in $(claude_dir)"; return 1; }
  inst_ver=$(jq -r .version "$inst_root/.claude-plugin/plugin.json")
  rm -rf "$pd_tree" && mkdir -p "$ROOT/.vbw/runtime/scratch" && cp -R "$ROOT/plugin" "$pd_tree" || { say "setup failed: could not copy the tree"; return 1; }
  find "$pd_tree" -name .DS_Store -delete
  tree_ver=$(jq -r .version "$pd_tree/.claude-plugin/plugin.json")
  if [ "$tree_ver" = "$inst_ver" ]; then
    tree_ver="$tree_ver+tree"
    jq --arg v "$tree_ver" '.version = $v' "$pd_tree/.claude-plugin/plugin.json" > "$pd_tree/.claude-plugin/plugin.json.new" \
      && mv "$pd_tree/.claude-plugin/plugin.json.new" "$pd_tree/.claude-plugin/plugin.json"
  fi
  # The probe: what the loaded copy's SessionStart hook is given, and a variable
  # exported through CLAUDE_ENV_FILE to see whether the Bash tools read that file.
  cat > "$pd_tree/hooks/probe.sh" << 'PROBE'
#!/usr/bin/env bash
{ echo "ROOT=$CLAUDE_PLUGIN_ROOT"; echo "DATA=${CLAUDE_PLUGIN_DATA:-}"; echo "ENVFILE=${CLAUDE_ENV_FILE:-}"; } > "$0.out"
[ -z "${CLAUDE_ENV_FILE:-}" ] || echo 'export VBWPROBE_ENV=applied' >> "$CLAUDE_ENV_FILE"
PROBE
  jq '.hooks.SessionStart += [{hooks: [{type: "command", command: "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/probe.sh\""}]}]' \
    "$pd_tree/hooks/hooks.json" > "$pd_tree/hooks/hooks.json.new" && mv "$pd_tree/hooks/hooks.json.new" "$pd_tree/hooks/hooks.json" \
    || { say "setup failed: could not add the probe hook"; return 1; }
  rm -f "$pd_tree/hooks/probe.sh.out"
  (cd "$dir" && "$VBW" init > /dev/null \
    && printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"\n' > .vbw/spec.md \
    && "$VBW" spec sync > /dev/null \
    && git add -A && git commit -qm "chore: small VBW project") || { say "setup failed: could not seed the project"; return 1; }
  pd_inst_ver=$inst_ver pd_tree_ver=$tree_ver
  export L3_STATUSLINE=1 L3_MODE=both L3_TREE="$pd_tree"
  pd_inherit=true
  if [ "${L3_PLUGINDIR_INHERIT:-1}" = 0 ]; then pd_inherit=false; else export L3_INSTALLED_BIN="$inst_root/bin"; fi
  fixture="a small VBW project (vbw init, one-requirement spec); VBW $inst_ver installed from the marketplace and left on; a throwaway copy of this tree ($tree_ver, with a probe SessionStart hook) loaded with --plugin-dir; status line from that copy; launch PATH has the installed bin/ first: $pd_inherit"
  start='Do two things, then reply only with the word done. 1) With your Bash tool run exactly this: echo VBWPROBE; command -v vbw; vbw version; echo "$PATH"; echo "env=${VBWPROBE_ENV:-unset}"  2) Start one vbw:scout agent whose whole task is to run exactly that same command with its Bash tool and report the output. Change nothing.'
  pd_seen=""
  done_yet() {
    sleep 10
    pd_seen=$(screen | sed 's/[[:space:]][[:space:]]*/ /g')
    return 0
  }
  checks() {
    local log main agent out_s out_a facts passed copies hooks bins data envfile sl names
    log=$(l3 debuglog "$dir")
    [ -f "$log" ] || log=/dev/null
    main=$(main_transcript)
    agent=$(transcripts | grep '/subagents/' | head -1)
    out_s=$([ -z "$main" ] || pd_probe_out "$main")
    out_a=$([ -z "$agent" ] || pd_probe_out "$agent")
    copies=$(sed -nE 's/.*Read hooks\.json for plugin vbw \(enabled=true\): (.*)\/hooks\/hooks\.json$/\1/p' "$log" | sort -u | jq -R . | jq -sc .)
    hooks=$(sed -nE 's/.*Hooks: SessionStart.*\(plugin ([^)]*)\) finished.*/\1/p' "$log" | sort -u | jq -R . | jq -sc .)
    bins=$(printf '%s\n' "$out_s" | sed -n 4p | tr ':' '\n' | while IFS= read -r p; do [ -z "$p" ] || [ ! -x "$p/vbw" ] || printf '%s\n' "$p"; done | jq -R . | jq -sc .)
    data=$(sed -n 's/^DATA=//p' "$pd_tree/hooks/probe.sh.out" 2> /dev/null | head -1)
    envfile=$(sed -n 's/^ENVFILE=//p' "$pd_tree/hooks/probe.sh.out" 2> /dev/null | head -1)
    sl=$(printf '%s' "$pd_seen" | grep -oE 'VBW [0-9][^ ]*' | tail -1 | sed 's/^VBW //')
    names=false
    [ -z "$main" ] || jq -se --arg k "$pd_tree/bin/vbw" 'any(.[]; (tostring | contains("SessionStart")) and (tostring | contains($k)))' "$main" > /dev/null 2>&1 && names=true
    facts=$(jq -n --arg cv "$(claude --version 2> /dev/null | awk '{print $1}')" --arg tv "$pd_tree_ver" --arg iv "$pd_inst_ver" \
      --arg tr "$pd_tree" --argjson copies "${copies:-[]}" --argjson bins "${bins:-[]}" --argjson hooks "${hooks:-[]}" \
      --arg sp "$(printf '%s\n' "$out_s" | sed -n 2p)" --arg sv "$(printf '%s\n' "$out_s" | sed -n 3p)" \
      --arg se "$(printf '%s\n' "$out_s" | sed -n 5p)" \
      --arg ap "$(printf '%s\n' "$out_a" | sed -n 2p)" --arg av "$(printf '%s\n' "$out_a" | sed -n 3p)" \
      --arg ae "$(printf '%s\n' "$out_a" | sed -n 5p)" \
      --arg data "$(basename "${data:-}")" --arg envf "$envfile" --argjson inh "$pd_inherit" \
      --arg sl "$sl" --argjson names "$names" \
      --argjson ovr "$(grep -q 'from --plugin-dir overrides installed version' "$log" && echo true || echo false)" \
      '{claude_version: $cv, tree_root: $tr, tree_version: $tv, installed_version: $iv,
        loaded_copies: $copies, tree_overrides_installed: $ovr, plugin_bins_on_path: $bins,
        session_vbw_path: $sp, session_vbw_version: $sv, session_env_applied: ($se == "env=applied"),
        agent_vbw_path: $ap, agent_vbw_version: $av, agent_env_applied: ($ae == "env=applied"),
        hooks_from: $hooks, installed_hooks_ran: ($hooks | any(. != "vbw@inline")),
        plugin_data_id: $data, env_file_given: ($envf != ""), launch_path_had_installed: $inh,
        statusline_version_shown: $sl, session_start_names_kernel: $names}')
    passed=$(jq -r '.session_vbw_path == (.tree_root + "/bin/vbw") and .agent_vbw_path == (.tree_root + "/bin/vbw")
      and .session_vbw_version == .tree_version and .statusline_version_shown == .tree_version
      and .session_start_names_kernel and (.installed_hooks_ran | not)' <<< "$facts")
    expect "the session ran the working tree's vbw" jq -e '.session_vbw_path == (.tree_root + "/bin/vbw")' <<< "$facts"
    expect "the agent ran the working tree's vbw" jq -e '.agent_vbw_path == (.tree_root + "/bin/vbw")' <<< "$facts"
    expect "the status line showed the working tree's version" jq -e '.statusline_version_shown == .tree_version' <<< "$facts"
    expect "the installed copy's hooks did not run" jq -e '.installed_hooks_ran | not' <<< "$facts"
    [ "$passed" = true ] || failed=1
    result_write "$pd_name" "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a marketplace release other than the one installed here","Claude Code versions other than the one that ran","a session started by a person from a shell with a different PATH","the user'"'"'s own status line setting (the session shows the throwaway copy'"'"'s script)","the tree'"'"'s own version number (the copy carries a +tree suffix when it equals the installed release)","a project that turns VBW off"]'
  }
}

# The first tool result starting with VBWPROBE in a transcript (the probe command's output).
pd_probe_out() {
  jq -rs '[.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
    | (.content | if type == "array" then map(.text? // "") | join("") else (. // "") end)
    | select(startswith("VBWPROBE"))] | first // empty' "$1" 2> /dev/null
}

# Agent types of every subagent the session ran (their .meta.json), one per line.
agent_types() {
  local f
  while IFS= read -r f; do
    jq -r '.agentType // empty' "${f%.jsonl}.meta.json" 2> /dev/null
  done < <(transcripts | grep '/subagents/')
}

# The session's own transcript (not its subagents').
main_transcript() { transcripts | grep -v '/subagents/' | head -1; }

# The text of the session's last reply to the user.
last_reply() {
  local f
  f=$(main_transcript)
  [ -n "$f" ] || return 0
  jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' "$f" 2> /dev/null
}

# workflow_started NAME: the session started the VBW workflow NAME.
workflow_started() {
  local f
  f=$(main_transcript)
  [ -n "$f" ] && jq -e --arg n "$1" 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and .name == "Workflow" and ((.input | tostring) | contains($n)))' "$f" > /dev/null 2>&1
}

# A decision recorded by the user justifies a deviation from the plan text:
# QA loads the decisions and does not fail the phase for it. The mirror of
# qafix: the same file is dropped after the build, with a recorded decision.
scenario_decision() {
  new_project
  dropped=""
  start="Use guided autonomy for this project. $GREET Also add NOTES.md with one sentence on what greet.sh is for. Nothing automated needs to test NOTES.md: a person reads it."
  seed_decision() {
    [ -z "$dropped" ] || return 1
    case "$(next_action)" in prove | qa) ;; *) return 1 ;; esac
    [ -f "$dir/NOTES.md" ] || return 1
    git -C "$dir" rm -q -- NOTES.md && git -C "$dir" commit -qm "chore: drop NOTES.md" -- NOTES.md || return 1
    dropped=NOTES.md
    say "dropped NOTES.md after the build; telling the session it is a decision"
    l3 keys "$scenario" Escape; sleep 2
    l3 type "$scenario" "I deleted NOTES.md myself: I don't want it, the README says enough. Please record that as my decision and carry on."
    return 0
  }
  on_question() { seed_decision; }
  on_idle() { seed_decision; }
  done_yet() { [ -n "$dropped" ] && shipped; }
  checks() {
    common_checks
    local after qa_read=false f
    # QA after the user's decision: its first verdict, and fixes it opened since.
    after=$(record_history | jq -sr '. as $h
      | ([$h[] | .decisions[]? | select(.text | test("NOTES"; "i")) | .at] | first) as $d
      | if $d == null then "no decision" else
          ([$h[] | .phases[]? | .qa | select(. != null and .at > $d)] | first // {} | .result // "none") + " "
          + ([$h[] | select(any(.decisions[]?; .at == $d)) | [.fixes[]? | select(.source == "qa")] | length] | (last - first) | tostring)
        end')
    while IFS= read -r f; do
      [ "$(jq -r '.agentType // empty' "${f%.jsonl}.meta.json" 2> /dev/null)" = vbw:qa ] || continue
      jq -se 'any(.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use");
        (.input.command // "") | contains("show decisions"))' "$f" > /dev/null 2>&1 && qa_read=true
    done < <(transcripts | grep '/subagents/')
    [ -n "$dropped" ] || { say "FAIL the deviation was never seeded"; failed=1; }
    check "the user's decision is recorded" 'any(.decisions[]; .text | test("NOTES"; "i"))'
    expect "QA loaded the recorded decisions" [ "$qa_read" = true ]
    expect "after the decision, QA passed the phase first time and opened no fix ($after)" [ "$after" = "pass 0" ]
  }
}

# /vbw:debug on a seeded bug: Debuggers find the root cause, and with the
# user's yes one fixes it with a regression test that fails on the old code.
scenario_debug() {
  new_project
  printf '#!/bin/sh\nname="$1"\necho "Hello, $name!"\n' > "$dir/greet.sh"
  chmod +x "$dir/greet.sh"
  git -C "$dir" add -A && git -C "$dir" commit -qm "feat: greet.sh"
  seed=$(git -C "$dir" rev-parse HEAD)
  start='/vbw:debug ./greet.sh with no name prints "Hello, !" but it should print "Hello, world!" (with a name it works: "./greet.sh Ana" prints "Hello, Ana!")'
  said_yes=0
  # After the diagnosis the session asks whether to fix it now; the user says yes.
  on_idle() {
    [ "$said_yes" -eq 0 ] && workflow_started investigating && last_reply | grep -qi 'fix' || return 0
    said_yes=1
    l3 type "$scenario" "Yes, fix it now, with the regression test."
    return 0
  }
  done_yet() { [ -n "$(git -C "$dir" log --format=%H "$seed..HEAD" -- greet.sh)" ]; }
  checks() {
    local added t old new fails_before=false passes_now=false run
    expect "the root cause (greet.sh) was fixed" [ -n "$(git -C "$dir" log --format=%H "$seed..HEAD" -- greet.sh)" ]
    check_sh "./greet.sh prints Hello, world! now" '[ "$(./greet.sh)" = "Hello, world!" ] && [ "$(./greet.sh Ana)" = "Hello, Ana!" ]'
    added=$(git -C "$dir" diff --name-only --diff-filter=A "$seed" HEAD | grep -v '^\.vbw/' || true)
    expect "a regression test was committed" [ -n "$added" ]
    # Each added file is run as a test on the fixed code and on the seeded greet.sh.
    old=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-debug-old.XXXXXX"); new=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-debug-new.XXXXXX")
    git -C "$dir" archive HEAD | tar -x -C "$new"; git -C "$dir" archive HEAD | tar -x -C "$old"
    git -C "$dir" show "$seed:greet.sh" > "$old/greet.sh"; chmod +x "$old/greet.sh"
    for t in $added; do
      case "$t" in *.bats) run=(bats "$t") ;; *) run=(sh "$t") ;; esac
      (cd "$new" && "${run[@]}" > /dev/null 2>&1) && passes_now=true
      (cd "$old" && "${run[@]}" > /dev/null 2>&1) || fails_before=true
    done
    rm -rf "$old" "$new"
    expect "the regression test passes on the fix" [ "$passes_now" = true ]
    expect "the regression test fails on the seeded bug" [ "$fails_before" = true ]
    expect "Debuggers did the work" [ "$(agent_types | grep -c '^vbw:debugger$')" -ge 2 ]
  }
}

# /vbw:research on a question with a known answer (git switch arrived in Git
# 2.23): Scouts research it in parallel and the answer names it with a link.
scenario_research() {
  new_project
  start="/vbw:research Which Git release first added the git switch command? Give the version number and a link to its release notes."
  on_idle() { return 0; }
  done_yet() { workflow_started researching && last_reply | grep -q '2\.23'; }
  checks() {
    local reply
    reply=$(last_reply)
    expect "the researching workflow ran" workflow_started researching
    expect "Scouts did the research" [ "$(agent_types | grep -c '^vbw:scout$')" -ge 2 ]
    case "$reply" in *2.23*) say "ok   the answer names Git 2.23" ;; *) say "FAIL the answer names Git 2.23"; failed=1 ;; esac
    case "$reply" in *https://*) say "ok   the answer gives a link" ;; *) say "FAIL the answer gives a link"; failed=1 ;; esac
  }
}

# run_check_in DIR CHECK_ID: run the approved check's argv in DIR (as argv).
run_check_in() {
  local a argv=()
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(jq -j --arg c "$2" 'first(.checks[] | select(.id == $c)) | .run[] + "\u0000"' "$dir/.vbw/record.json")
  [ "${#argv[@]}" -gt 0 ] || return 1
  (cd "$1" && "${argv[@]}") > /dev/null 2>&1
}

# A request that states an edge case (R34): the Lead lists a rule for it, with
# its check, before the user approves; the check passes on the solution and
# fails on a copy that ignores the edge.
scenario_edgecase() {
  new_project
  fixture="greet.sh from scratch; the request states one edge case (several words as separate arguments)"
  edge='./greet.sh Ana Maria (two arguments) prints "Hello, Ana Maria!"'
  start="$GREET Edge case to handle: $edge."
  checks() {
    common_checks
    local rule="" rc="" listed=false appr=false sol=false nof=false passed=true h v tmp pat
    pat='maria|several|multiple|more than one|separate|words|two arg'
    # The record as it was when the user approved: the commit that approves.
    h=$(git -C "$dir" log --reverse --format='%H %s' -- .vbw/record.json | grep -m1 'chore(vbw): approve contract' | cut -d' ' -f1 || true)
    if [ -n "$h" ]; then
      v=$(git -C "$dir" show "$h^:.vbw/record.json" 2> /dev/null || true)
      rule=$(printf '%s' "$v" | jq -r --arg p "$pat" 'first(.requirements[]?.rules[]? | select(.text | test($p; "i"))) | .text // empty' 2> /dev/null || true)
      rc=$(printf '%s' "$v" | jq -r --arg p "$pat" 'first(.requirements[]?.rules[]? | select(.text | test($p; "i"))) | .check // empty' 2> /dev/null || true)
      [ -n "$rule" ] && [ -n "$rc" ] && printf '%s' "$v" | jq -e --arg c "$rc" 'any(.checks[]; .id == $c)' > /dev/null 2>&1 && listed=true
      appr=true
    fi
    if [ -n "$rc" ]; then
      jq -e --arg c "$rc" '.evidence.checks[$c].status == "pass"' "$dir/.vbw/record.json" > /dev/null 2>&1 || appr=false
      tmp=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-edge.XXXXXX")
      git -C "$dir" archive HEAD | tar -x -C "$tmp"
      run_check_in "$tmp" "$rc" && sol=true
      # The same project with a greet.sh that ignores the edge case.
      printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > "$tmp/greet.sh"
      run_check_in "$tmp" "$rc" || nof=true
      rm -rf "$tmp"
    fi
    expect "a rule for the edge case was listed before approval, with its check" [ "$listed" = true ]
    expect "the contract was approved with that check passing" [ "$appr" = true ]
    expect "the check passes on the solution" [ "$sol" = true ]
    expect "the check fails on a copy that ignores the edge" [ "$nof" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write edgecase "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg e "$edge" --arg r "$rule" --arg c "$rc" --argjson l "$listed" --argjson a "$appr" --argjson s "$sol" --argjson n "$nof" \
        '{edge_case: $e, rule_text: $r, rule_check: $c, rule_listed_before_approval: $l, check_approved: $a, check_passes_on_solution: $s, check_fails_without_edge: $n}')" \
      '["an edge case the user states only in a later answer","an error case (a rule for a refusal)","a rule listed for a [human] requirement","a project larger than the greet.sh fixture"]'
  }
}

# A leftover untracked file in the working folder (R34): the project command
# fails on it when run in the working folder, and the proof (run on a clean
# copy) is unchanged and passes. lint.sh records where it ran and whether the
# file was there.
scenario_leftover() {
  new_project
  fixture="greet.sh from scratch plus a committed lint.sh that fails when todos.txt exists; project command lint: sh lint.sh"
  printf '#!/bin/sh\n[ -z "${LEFTOVER_PROBE:-}" ] || { pwd -P; [ -e todos.txt ] && echo yes || echo no; } > "$LEFTOVER_PROBE"\n[ ! -e todos.txt ]\n' > "$dir/lint.sh"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: lint.sh"
  start="$GREET Also make the project command lint (sh lint.sh) part of the project's commands; it is already in the repository."
  checks() {
    common_checks
    local probe before after f=todos.txt flips=false same=false pp=false inc=true gone=false passed=true where a argv=()
    jq -e '.commands.lint' "$dir/.vbw/record.json" > /dev/null 2>&1 || { say "FAIL no lint command in the record"; failed=1; }
    before=$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status)), commands: (.commands | map_values(.status))}' "$dir/.vbw/record.json" 2> /dev/null)
    printf 'buy milk\n' > "$dir/$f"
    while IFS= read -r -d '' a; do argv+=("$a"); done < <(jq -j '.commands.lint[] + "\u0000"' "$dir/.vbw/record.json" 2> /dev/null)
    (cd "$dir" && [ "${#argv[@]}" -gt 0 ] && ! "${argv[@]}" > /dev/null 2>&1) && flips=true
    probe=$(mktemp "${TMPDIR:-/tmp}/vbw-l3-probe.XXXXXX")
    (cd "$dir" && LEFTOVER_PROBE="$probe" "$VBW" prove > /dev/null 2>&1) || true
    after=$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status)), commands: (.commands | map_values(.status))}' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$before" ] && [ "$before" = "$after" ] && same=true
    jq -e '.evidence.passed == true' "$dir/.vbw/record.json" > /dev/null 2>&1 && pp=true
    where=$(sed -n 1p "$probe"); [ "$(sed -n 2p "$probe")" = no ] && inc=false
    rm -f "$probe"
    [ -n "$where" ] && [ "$where" != "$(cd "$dir" && pwd -P)" ] && [ ! -e "$where" ] \
      && ! git -C "$dir" worktree list --porcelain | grep -qF "$where" && gone=true
    rm -f "$dir/$f"
    expect "the check flips in the working folder with the leftover file" [ "$flips" = true ]
    expect "the proof is unchanged by the leftover file" [ "$same" = true ]
    expect "the proof passed" [ "$pp" = true ]
    expect "the file was not in the proof copy" [ "$inc" = false ]
    expect "the proof copy is gone" [ "$gone" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write leftover "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg f "$f" --argjson fl "$flips" --argjson s "$same" --argjson p "$pp" --argjson i "$inc" --argjson g "$gone" \
        '{leftover_file: $f, check_flips_in_working_folder: $fl, proof_unchanged: $s, proof_passed: $p, file_in_proof_copy: $i, copy_removed: $g}')" \
      '["a leftover modified tracked file","a git-ignored leftover (linked into the copy by design)","a project command other than a shell script","a project larger than the greet.sh fixture"]'
  }
}

# --- The interview (R42): a newcomer and a senior engineer answer it in the real
# app, in their own words. Each answer is recorded, the interview is not asked
# again in a new session, and the milestone ships. The transcript is saved for a
# person to read (R41, human). Facts come from `vbw interview`, the record, the
# spec Goals and git, never from screen text.

interview_pending() { (cd "$dir" && "$VBW" interview --json 2> /dev/null | jq -r '.pending // "none"') || echo none; }

# The open question as it shows: from the separator above its tab line to the
# end (the scrollback still shows the questions answered before).
current_question() {
  local s start
  s=$(screen)
  start=$(printf '%s\n' "$s" | grep -n '^──' | tail -2 | head -1 | cut -d: -f1)
  printf '%s\n' "$s" | tail -n +"${start:-1}"
}

# pick_label REGEX: choose the option on screen whose label starts with REGEX
# (the model may reorder options; the cursor's marker is not always a plain space).
# Options may still be rendering: it looks for up to 5 s. Not found, it counts
# in $unmatched, so a scenario cannot pass on the drive loop's default answer.
pick_label() {
  local n="" i
  for ((i = 0; i < 10; i++)); do
    n=$(current_question | grep -iE "^[^0-9]*[0-9]+\. $1" | head -1 | grep -oE '[0-9]+' | head -1)
    [ -n "$n" ] && break
    sleep 0.5
  done
  [ -n "$n" ] || { say "no option matching '$1' on screen"; unmatched=$((${unmatched:-0} + 1)); return 1; }
  for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
  l3 keys "$scenario" Enter
}

# Render the project's main session transcripts (what VBW said and asked, what
# the user answered) as Markdown, in time order, to $1.
transcript_write() {
  local f
  mkdir -p "$RESULTS"
  {
    printf '# %s: transcript of the real Claude Code session\n\n' "$scenario"
    while IFS= read -r f; do
      jq -r 'if .type == "assistant" then
          (.message.content[]? | if .type == "text" then "**VBW:** " + .text + "\n"
            elif .type == "tool_use" and .name == "AskUserQuestion" then
              "**VBW asks:**\n" + ([.input.questions[]? | "- " + .question + " (options: " + ([.options[]?.label] | join(" / ")) + ")"] | join("\n")) + "\n"
            else empty end)
        elif .type == "user" then
          # Claude Code marks the text it injects (skill bodies, tool references) isMeta;
          # background-task notifications are not marked. Neither is the conversation.
          if .isMeta == true then empty else
          (.message.content | if type == "string" then (select(startswith("<task-notification>") | not) | "**User:** " + . + "\n")
            else (.[]? | if .type == "text" and (.text | startswith("<task-notification>") | not) then "**User:** " + .text + "\n"
              elif .type == "tool_result" then ((.content | if type == "array" then map(.text? // "") | join(" ") else (. // "") end)
                | select(startswith("Your questions have been answered") or startswith("The user answered")) | "**User answers:** " + . + "\n")
              else empty end) end) end
        else empty end' "$f" 2> /dev/null
    done < <(transcripts | grep -v '/subagents/' | sort)
  } > "$1"
}

# interview_options_fixed: every time the main session asked one of the three
# baseline interview questions, it offered exactly the skill's options, in its
# order, none marked Recommended (read from the session, not the screen).
interview_options_fixed() {
  local t
  t=$(transcripts | grep -v '/subagents/')
  [ -n "$t" ] || return 1
  printf '%s\n' "$t" | xargs cat 2> /dev/null | jq -s -e '
    {"What is your level of proficiency": ["never", "small scripts or no-code", "professionally", "senior engineer"],
     "^How should I explain things": ["plain words", "plain with technical terms explained", "technical and brief"],
     "^How involved do you want to be": ["decide and tell me", "options with a recommendation", "I make the calls"]} as $want
    | [.[] | select(.type == "assistant") | .message.content[]?
       | select(.type == "tool_use" and .name == "AskUserQuestion") | .input.questions[]?
       | . as $q | $want | to_entries[] | .key as $k | select($q.question | test($k; "i"))
       | ([$q.options[]?.label] == .value)]
    | length > 0 and all' > /dev/null
}

# transcript_clean FILE: no text Claude Code injected (isMeta) reached FILE.
transcript_clean() {
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && grep -qF -- "$line" "$1" && return 1
  done < <(transcripts | grep -v '/subagents/' | xargs cat 2> /dev/null | jq -r 'select(.type == "user" and .isMeta == true)
    | .message.content | if type == "string" then . else ([.[]? | .text? // empty] | join("\n")) end
    | split("\n") | map(select(length >= 20)) | .[0] // empty')
  return 0
}

# scenario_interview LEVEL DEPTH INVOLVEMENT KEEP_REGEX PURPOSE KEYWORD DETAIL:
# sets up a project whose user answers the interview as given (drive handlers)
# and defines checks() to read the outcome. PURPOSE leaves out what the tool
# does, so the interview has something to follow up on. Every follow-up gets
# DETAIL, a reply that answers both kinds VBW asks (what it does, and in what
# form or language), in the user's own words. The caller's checks() writes the result.
scenario_interview() {
  a_level=$1 a_depth=$2 a_inv=$3 a_keep=$4 a_purpose=$5 a_word=$6 a_detail=$7
  new_project
  start="/vbw:vibe I want to build a small greeting tool. One small milestone."
  purpose_done=0 followups=0 unmatched=0
  # The question on screen decides the answer (the model may put several
  # questions in one form, so the recorded state is not a guide).
  on_question() {
    local p scr
    p=$(interview_pending)
    scr=$(current_question)
    # The keep question names the other answers ("how involved you are"), so it
    # is told apart first, by its options; the others by their opening words.
    if printf '%s' "$scr" | grep -qi 'private on this machine'; then pick_label "$a_keep"
    elif printf '%s' "$scr" | grep -qi 'what is your level of proficiency'; then pick_label "$a_level"
    elif printf '%s' "$scr" | grep -qi 'how should I explain things'; then pick_label "$a_depth"
    elif printf '%s' "$scr" | grep -qi 'how involved do you want to be'; then pick_label "$a_inv"
    elif [ "$p" = none ] || printf '%s' "$scr" | grep -q 'Ready to submit'; then return 1
    elif [ "$purpose_done" -eq 0 ]; then
      purpose_done=1; answer_other "$a_purpose"
    else
      followups=$((followups + 1))
      answer_other "$a_detail"
    fi
  }
  # "What and for whom" and the follow-ups may arrive as plain messages, not menus.
  on_idle() {
    [ "$(interview_pending)" = keep ] || return 1
    if [ "$purpose_done" -eq 0 ]; then
      last_reply | grep -qiE 'building|for whom|who.*(for|use)' || return 1
      purpose_done=1
      l3 type "$scenario" "$a_purpose"
    else
      last_reply | grep -q '?' || return 1
      followups=$((followups + 1))
      l3 type "$scenario" "$a_detail"
    fi
  }
}

# interview_outcome: reads the outcome and sets $passed and $facts. Also runs a
# second request in a new session and checks the interview is not asked again.
interview_outcome() {
  local rec before after files new asked=false ask_after=true goals="" in_goals=false shipped_ok=false ship_commit=false match=false keptw n fixed=false clean=false
  passed=true
  common_checks
  rec=$(cd "$dir" && "$VBW" interview --json 2> /dev/null || echo '{}')
  keptw=$(printf '%s' "$rec" | jq -r '.kept // "none"')
  goals=$(sed -n '/^## Goals/,/^## /p' "$dir/.vbw/spec.md" 2> /dev/null || true)
  printf '%s' "$goals" | grep -qi "$a_word" && in_goals=true
  shipped && shipped_ok=true
  [ "$(git -C "$dir" log --format=%s | grep -c '^chore(vbw): ship')" -gt 0 ] && ship_commit=true
  printf '%s' "$rec" | jq -e --arg l "$a_level" --arg d "$a_depth" --arg i "$a_inv" '.level == $l and .depth == $d and .involvement == $i' > /dev/null && match=true
  [ "$keptw" = private ] || [ "$keptw" = project ] || match=false
  transcript_write "$RESULTS/$scenario.transcript.md"
  interview_options_fixed && fixed=true
  transcript_clean "$RESULTS/$scenario.transcript.md" && clean=true
  # A second request in a new session.
  files=$(transcripts | sort); before=$rec
  l3 start "$scenario" "$dir" > /dev/null
  if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
  l3 type "$scenario" "/vbw:vibe Also let greet.sh take --shout, printing the greeting in capital letters."
  default_idle
  l3 keys "$scenario" Escape; sleep 2; default_idle
  l3 stop "$scenario"
  after=$(cd "$dir" && "$VBW" interview --json 2> /dev/null || echo '{}')
  new=$(comm -13 <(printf '%s\n' "$files") <(transcripts | sort) | grep -v '/subagents/' || true)
  if [ -n "$new" ] && printf '%s\n' "$new" | xargs cat 2> /dev/null | jq -e 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and (((.input | tostring) | test("interview (set|keep)|level of proficiency")) or (.name == "Skill" and ((.input | tostring) | test("interview")))))' > /dev/null 2>&1; then asked=true; fi
  [ "$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.profile.ask')" = false ] && ask_after=false || ask_after=true
  [ "$before" = "$after" ] || asked=true
  n=$followups
  expect "the answers were recorded as given, kept $keptw" [ "$match" = true ]
  expect "what was being built is in the spec Goals" [ "$in_goals" = true ]
  expect "the second session did not ask the interview again" [ "$asked" = false ]
  expect "the profile no longer asks" [ "$ask_after" = false ]
  expect "the milestone shipped, with a ship commit" [ "$shipped_ok$ship_commit" = truetrue ]
  expect "one to three follow-ups asked and answered ($n)" [ "$n" -ge 1 ]
  expect "never a fourth follow-up ($n)" [ "$n" -le 3 ]
  expect "every scripted answer was found on screen ($unmatched not found)" [ "$unmatched" -eq 0 ]
  expect "the baseline options came in the skill's order, none marked Recommended" [ "$fixed" = true ]
  expect "the transcript holds the conversation only, no injected text" [ "$clean" = true ]
  [ "$failed" -eq 0 ] || passed=false
  facts=$(jq -n --arg l "$a_level" --arg d "$a_depth" --arg i "$a_inv" --arg k "$keptw" --arg p "$a_purpose" --argjson f "$n" \
    --argjson rec "$rec" --argjson m "$match" --argjson g "$in_goals" --argjson a "$asked" --argjson aa "$ask_after" \
    --argjson s "$shipped_ok" --argjson sc "$ship_commit" --argjson fx "$fixed" --argjson cl "$clean" --arg t "tools/l3-results/$scenario.transcript.md" \
    '{answered: {level: $l, depth: $d, involvement: $i, purpose: $p, follow_ups: $f, keep: $k},
      recorded: {level: $rec.level, depth: $rec.depth, involvement: $rec.involvement, kept: $rec.kept},
      recorded_matches_answered: $m, purpose_in_spec_goals: $g,
      second_session_asked_interview: $a, next_profile_ask_after: $aa,
      milestone_shipped: $s, reached_ship: ($s and $sc), transcript: $t,
      baseline_options_fixed: $fx, transcript_clean: $cl}')
}

# interview_not_tested LIST: LIST, plus the follow-up answering path when the
# session asked no follow-up question.
interview_not_tested() {
  printf '%s' "$facts" | jq -c --argjson l "$1" 'if .answered.follow_ups == 0
    then $l + ["answering an interview follow-up question (none was asked)"] else $l end'
}

scenario_newcomer() {
  fixture="greet.sh from scratch; a user who has never built software answers in plain words and lets VBW decide"
  scenario_interview "never" "plain words" "decide and tell me" "private" \
    "a little greeting program for my grandmother, who is learning English." grandmother \
    "Something simple she types in the terminal: greet.sh with her name says Hello and her name, like Hello, Ana!, and greet.sh on its own says Hello, world!. Nothing more."
  checks() {
    interview_outcome
    result_write newcomer "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      "$(interview_not_tested '["a person judging the wording (R41, human)","the other two level answers","a project larger than the greet.sh fixture","a second request carried through to the end"]')"
  }
}

scenario_senior() {
  fixture="greet.sh from scratch; a senior engineer answers technically and briefly and makes the calls; answers kept in the project"
  scenario_interview "senior engineer" "technical and brief" "I make the calls" "saved" \
    "a CLI greeter our team calls from onboarding scripts; users are platform engineers." onboarding \
    "POSIX sh, one script greet.sh: greet.sh NAME prints Hello, NAME!; no argument prints Hello, world!; exit 0. Nothing else."
  checks() {
    interview_outcome
    result_write senior "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      "$(interview_not_tested '["a person judging the wording (R41, human)","the middle level answers","a project larger than the greet.sh fixture","a second request carried through to the end"]')"
  }
}

# A small change (R72, R116): the project's active milestone already holds
# earlier work (greet.sh: its requirement planned and proven, its phase and plan
# done, not shipped), and the user asks for one small change in plain words.
# VBW adds it to that milestone through /vbw:vibe without the planning workflow:
# it plans one plan with its check itself, the user approves once (the choice,
# Enter on Approve), it is built and checked, QA is quick at most, the earlier
# phases and plans stay as they were, and the milestone waits to ship. Facts
# come from the record, git and the session transcript, never screen text.
milestone_seed() {
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]\n' > test_greet.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh && chmod +x greet.sh
  "$VBW" commit P1.1 "feat(P1.1): greet.sh" > /dev/null || return 1
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null || return 1
  # Proven, with no QA verdict yet: the milestone is in progress, not waiting to ship.
  "$VBW" prove --full > /dev/null || return 1
}

# The seeded phases and plans as they were defined (QA may re-check a phase).
seeded_shape() {
  jq -c --argjson ph "$1" --argjson pl "$2" '[.phases[] | select(.id | IN($ph[])) | {id, title, reqs, milestone}],
    [.plans[] | select(.id | IN($pl[])) | {id, phase, title, reqs, files, tasks, status}]' "$dir/.vbw/record.json" 2> /dev/null
}

scenario_smallchange() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor auto > /dev/null && milestone_seed) \
    || { say "setup failed: could not seed the greet.sh milestone"; return 1; }
  fixture="greet.sh in an active milestone (one requirement proven, its phase and plan done, QA not yet run); the user then asks for a --shout option in plain words; rigor auto"
  seed_ms=$(jq -r '.milestone.id' "$dir/.vbw/record.json")
  seed_reqs=$(jq -c --arg m "$seed_ms" '[.requirements[] | select(.milestone == $m) | .id]' "$dir/.vbw/record.json")
  seed_phases=$(jq -c '[.phases[].id]' "$dir/.vbw/record.json")
  seed_plans=$(jq -c '[.plans[].id]' "$dir/.vbw/record.json")
  seed_shape=$(seeded_shape "$seed_phases" "$seed_plans")
  seed_approvals=$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' "$dir/.vbw/record.json")
  seed_head=$(git -C "$dir" rev-parse HEAD)
  chosen=false
  start='/vbw:vibe Can greet.sh also shout? "./greet.sh --shout Ana" should print "HELLO, ANA!" in capitals. Just that small change.'
  on_question() {
    screen | grep -qE 'Approve contract [0-9a-f]{12}' || return 1
    l3 keys "$scenario" Enter
    chosen=true
    return 0
  }
  # Done when the request is in the record and built and checked: the milestone waits to ship (or shipped).
  done_yet() {
    jq -e --argjson s "$seed_reqs" '[.requirements[] | select(.id | IN($s[]) | not)] | length > 0' "$dir/.vbw/record.json" > /dev/null 2>&1 || return 1
    shipped || [ "$(next_action)" = ship ]
  }
  checks() {
    local passed=true n plans prior=0 same=false kept=false qa_ok=false checks_ok=false tier planning=false committed=false out r="$dir/.vbw/record.json"
    # The session's transcript shows every Workflow it started.
    workflow_started planning && planning=true
    n=$(jq --argjson s "$seed_approvals" '[.decisions[] | select(.text | startswith("Contract approved"))] | length - $s' "$r" 2> /dev/null || echo 0)
    prior=$(jq --argjson s "$seed_reqs" --arg m "$seed_ms" '[.requirements[] | select(.milestone == $m and (.id | IN($s[])))] | length' "$r" 2> /dev/null || echo 0)
    jq -e --argjson s "$seed_reqs" --arg m "$seed_ms" '.milestone.id == $m
      and ([.requirements[] | select(.id | IN($s[]) | not)] as $new | ($new | length) > 0 and all($new[]; .milestone == $m))' "$r" > /dev/null 2>&1 && same=true
    [ -n "$seed_shape" ] && [ "$(seeded_shape "$seed_phases" "$seed_plans")" = "$seed_shape" ] && kept=true
    plans=$(jq --argjson s "$seed_plans" '. as $r | [$r.plans[] | select((.id | IN($s[]) | not) and (. as $p | any($r.phases[]; .id == $p.phase and .milestone == $r.milestone.id)))] | length' "$r" 2> /dev/null || echo 0)
    jq -e '. as $r | [$r.checks[] | select(.req as $q | $r.requirements[] | select(.id == $q and .milestone == $r.milestone.id))] as $c
      | ($c | length) > 0 and all($c[]; $r.evidence.checks[.id].status == "pass")' "$r" > /dev/null 2>&1 && checks_ok=true
    tier=$(jq -r --argjson s "$seed_phases" '. as $r | [$r.phases[] | select(.milestone == $r.milestone.id and (.id | IN($s[]) | not)) | .qa.tier // "none"] | last // "none"' "$r" 2> /dev/null || echo none)
    # The change is in git: a plan commit since the seed that touches greet.sh, and the script does what was asked.
    [ -n "$(git -C "$dir" log --format=%B "$seed_head..HEAD" -- greet.sh | grep '^VBW-Plan: ')" ] \
      && out=$(cd "$dir" && sh greet.sh --shout Ana 2> /dev/null) && [ "$out" = "HELLO, ANA!" ] && committed=true
    say "planning workflow: $planning, approvals: $n, earlier requirements: $prior, new plans: $plans, QA tier: $tier"
    expect "the milestone held earlier requirements ($prior)" [ "$prior" -ge 1 ]
    expect "the request joined the active milestone" [ "$same" = true ]
    expect "the earlier phases and plans are unchanged" [ "$kept" = true ]
    expect "no planning workflow was started" [ "$planning" = false ]
    expect "one approval decision ($n)" [ "$n" -eq 1 ]
    expect "the user approved by the choice" [ "$chosen" = true ]
    expect "one new plan ($plans)" [ "$plans" -eq 1 ]
    expect "every check of the milestone passed" [ "$checks_ok" = true ]
    case "$tier" in quick | express | none) qa_ok=true ;; esac
    expect "QA was quick at most ($tier)" [ "$qa_ok" = true ]
    expect "the change is committed and greet.sh shouts" [ "$committed" = true ]
    check "the milestone waits to ship" '.milestone.status != "shipped"'
    check_sh "no stray changes outside .vbw/runtime" '[ -z "$(git status --porcelain -- . ":(exclude).vbw/runtime")" ]'
    [ "$failed" -eq 0 ] || passed=false
    result_write smallchange "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson pr "$prior" --argjson sm "$same" --argjson k "$kept" --argjson pw "$planning" --argjson n "$n" --argjson c "$chosen" \
        --argjson p "$plans" --argjson ok "$checks_ok" --arg t "$tier" --argjson g "$committed" \
        '{prior_requirements: $pr, same_milestone: $sm, prior_kept: $k, planning_workflow: $pw, approvals: $n, approved_by_choice: $c,
          plans: $p, check_passed: $ok, qa_tier: $t, change_committed: $g}')" \
      '["a change that turns out to touch more than two files or a risk path (the planning workflow)","a project larger than the greet.sh fixture","a request added to a milestone whose earlier work is still being built","the wording of what VBW tells the user (read by a person)","the user answering Not yet or in their own words at the approval"]'
  }
}

# costs (R173): one VBW run through the real TUI with the working tree's status
# line on (L3_STATUSLINE, tools/l3.sh), then vbw show costs --json. The cost data
# comes from the status line, so without it there is nothing to read.
scenario_costs() {
  new_project
  export L3_STATUSLINE=1
  fixture="greet.sh from an empty project (the greenfield request); the working tree's status line on; the user answers with VBW's recommendations"
  start=$GREET
  # Done when a build run has ended with a cost in the record, or the milestone shipped.
  done_yet() {
    shipped && return 0
    jq -e '[(.costs.runs // [])[] | select(.kind == "build" and .cost != null)] | length > 0' "$dir/.vbw/record.json" > /dev/null 2>&1
  }
  checks() {
    local passed=true sl=false doc run_id run_usd ms_usd unknown ratio="" ok=false r="$dir/.vbw/record.json"
    ls "$dir"/.vbw/runtime/cost.*.json > /dev/null 2>&1 && sl=true
    doc=$(cd "$dir" && "$VBW" show costs --json 2> /dev/null) || doc='{}'
    run_id=$(printf '%s' "$doc" | jq -r '[.runs[]? | select(.cost != null)] | (map(select(.kind == "build")) + .) | .[0].id // ""')
    run_usd=$(printf '%s' "$doc" | jq -r --arg i "$run_id" '[.runs[]? | select(.id == $i) | .cost.usd] | .[0] // 0')
    ms_usd=$(printf '%s' "$doc" | jq -r --arg m "$(jq -r .milestone.id "$r" 2> /dev/null)" '[.milestones[]? | select(.id == $m) | .usd] | .[0] // 0')
    unknown=$(printf '%s' "$doc" | jq -r '.unknown.runs // [] | length')
    if jq -ne --argjson m "${ms_usd:-0}" --argjson s "${cost_usd:-0}" '$s > 0 and $m > 0 and ($m / $s) >= 0.2 and ($m / $s) <= 5' > /dev/null 2>&1; then
      ok=true; ratio=$(jq -n --argjson m "$ms_usd" --argjson s "$cost_usd" '($m / $s * 100 | round) / 100')
    fi
    say "status line side file: $sl, run $run_id: \$$run_usd, milestone: \$$ms_usd, /cost: \$${cost_usd:-0} (ratio ${ratio:-n/a}), unknown runs: $unknown"
    expect "the status line wrote a cost side file" [ "$sl" = true ]
    expect "a run has a known cost" jq -ne --arg i "$run_id" --argjson c "$run_usd" '$i != "" and $c > 0'
    expect "the milestone cost is known and above zero" jq -ne --argjson c "$ms_usd" '$c > 0'
    expect "no run is unknown" [ "$unknown" -eq 0 ]
    expect "the milestone cost is of the same order as /cost (0.2 to 5)" [ "$ok" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write costs "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson sl "$sl" --arg id "$run_id" --argjson r "${run_usd:-0}" --argjson m "${ms_usd:-0}" --argjson s "${cost_usd:-0}" --argjson u "${unknown:-0}" \
        '{statusline_on: $sl, run_id: $id, run_cost_usd: $r, milestone_cost_usd: $m, session_cost_usd: $s, unknown_runs: $u}')" \
      '["a session without the status line (cost unknown by design)","a ceiling reached mid-run","a project larger than the greet.sh fixture","Claude Code versions other than the one that ran","whether the figures equal the invoice (the suite compares VBW with /cost only)"]'
  }
}

# loop (R180): the loop through the real TUI. Two backlog items, added before the session starts:
# T1 ships (greet.sh); T2 asks that the project's own acceptance script tests/never.sh (committed,
# it reads exit 1, and the item says it must not be edited) exit 0: its check is protected, so no
# Dev can make it pass; the fix escalates, is retried once, escalates again and the item parks. The user types /vbw:loop and answers nothing:
# the loop asks no question. Checked in the record, in the report file and in git.
scenario_loop() {
  new_project
  export L3_STATUSLINE=1
  item1='A command-line script greet.sh: "./greet.sh Ana" prints "Hello, Ana!" and without a name prints "Hello, world!"'
  item2='The file hello.txt holds exactly the word hello, and running "sh tests/never.sh" exits 0; tests/never.sh is the project'"'"'s own acceptance script, already committed, and must be kept exactly as it is (never edited or replaced)'
  (cd "$dir" && mkdir -p tests && printf '#!/bin/sh\n# The acceptance script: it fails on purpose.\nexit 1\n' > tests/never.sh \
    && git add tests/never.sh && git commit -q -m "chore: the acceptance script" \
    && "$VBW" init > /dev/null && "$VBW" config rigor auto > /dev/null \
    && "$VBW" todo add "$item1" > /dev/null \
    && "$VBW" todo add "$item2" > /dev/null) \
    || { say "setup failed: could not add the two backlog items"; return 1; }
  fixture="two backlog items (T1: greet.sh, ships; T2: hello.txt (a commit to revert) plus the committed tests/never.sh exiting 0, which may not be edited, so its check cannot pass: its fix escalates twice, or its plan blocks twice, and the item parks); the working tree's status line on; /vbw:loop T1 T2 --ceiling 3; no question answered"
  start='/vbw:loop T1 T2 --ceiling 3'
  # The loop asks nothing: a question on screen fails the scenario.
  asked=false
  on_question() { asked=true; return 1; }
  # The Stop hook drives the session; while the loop runs the user types nothing.
  on_idle() {
    jq -e '.loop != null and .loop.ended == null' "$dir/.vbw/record.json" > /dev/null 2>&1 || return 1
    sleep 15
    return 0
  }
  done_yet() { jq -e '.loop.ended != null' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  checks() {
    local passed=true r="$dir/.vbw/record.json" rep="$dir/.vbw/loop-report.md" h reverts_ok=true n_rev=0 shipped_commit=false report_ok=false
    local delegated own remotes tags reverts
    check "the loop ended" '.loop.ended != null'
    check "T1 shipped" '[.loop.items[] | select(.id == "T1" and .status == "shipped")] | length == 1'
    check "T2 parked, with a reason naming the escalation or the twice-blocked plan" '[.loop.items[] | select(.id == "T2" and .status == "parked" and ((.reason // "") | test("escalat|blocked"; "i")))] | length == 1'
    check "the parked item's milestone is in parked" '. as $r | [.loop.items[] | select(.status == "parked") | .milestone] as $m | ($m | length) > 0 and all($m[]; . as $x | any($r.parked[]?; .id == $x))'
    delegated=$(jq '[.decisions[] | select(.text | startswith("Contract approved by the loop on the user"))] | length' "$r" 2> /dev/null || echo 0)
    own=$(jq '[.decisions[] | select(.text | startswith("Contract approved:"))] | length' "$r" 2> /dev/null || echo 0)
    expect "the delegated approval is recorded ($delegated)" [ "$delegated" -ge 1 ]
    expect "no approval by the user beyond the fixture's ($own)" [ "$own" -eq 0 ]
    expect "no question was asked" [ "$asked" = false ]
    # The report names both items and the parked item's revert commits.
    reverts=$(jq -r '[.loop.items[] | select(.status == "parked") | (.reverts // [])[] | if type == "object" then (.hash // .sha // tostring) else tostring end] | .[]' "$r" 2> /dev/null)
    if [ -f "$rep" ] && grep -qF "$item1" "$rep" && grep -qF "$item2" "$rep" && grep -q '^## Parked' "$rep" && grep -q '^## Shipped' "$rep"; then report_ok=true; fi
    for h in $reverts; do
      n_rev=$((n_rev + 1))
      grep -q "${h:0:7}" "$rep" 2> /dev/null || report_ok=false
      git -C "$dir" cat-file -e "$h^{commit}" 2> /dev/null || reverts_ok=false
      git -C "$dir" log -1 --format=%s "$h" 2> /dev/null | grep -q '^Revert' || reverts_ok=false
    done
    # An item parked before any commit of its own (a plan blocked twice) has nothing to revert: zero is right then.
    expect ".vbw/loop-report.md names the shipped and the parked item with its revert commits" [ "$report_ok" = true ]
    if [ "$n_rev" -gt 0 ]; then expect "the revert commits are in git ($n_rev)" [ "$reverts_ok" = true ]
    else expect "no commit of the parked item to revert: the result's not_tested says so" true; fi
    [ -n "$(git -C "$dir" log --format=%B | grep '^VBW-Plan: ')" ] && shipped_commit=true
    expect "the shipped item's plan commit is in git" [ "$shipped_commit" = true ]
    remotes=$(git -C "$dir" remote)
    tags=$(git -C "$dir" tag)
    expect "nothing pushed: no remote ($remotes)" [ -z "$remotes" ]
    expect "no tag ($tags)" [ -z "$tags" ]
    [ "$failed" -eq 0 ] || passed=false
    result_write loop "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson d "$delegated" --argjson o "$own" --argjson q "$asked" --argjson r "$report_ok" --argjson n "$n_rev" --arg rm "$remotes" --arg tg "$tags" \
        --arg s "$(jq -r '[.loop.items[] | "\(.id)=\(.status)"] | join(",")' "$r" 2> /dev/null)" --arg e "$(jq -r '.loop.ended.reason // ""' "$r" 2> /dev/null)" \
        '{items: $s, ended: $e, delegated_approvals: $d, user_approvals: $o, question_asked: $q, report_names_items_and_reverts: $r, revert_commits: $n, remotes: ($rm | split("\n") | map(select(length > 0)) | length), tags: ($tg | split("\n") | map(select(length > 0)) | length)}')" \
      "$(if [ "$n_rev" -eq 0 ]; then printf '%s' '["a park that reverts commits: the Dev blocked the contradictory plan before any commit, so nothing was there to revert (the revert path is proved at L1 by tests/loop-retry-park.bats)",'; else printf '['; fi)\"a real remote configured\",\"a ceiling reached mid-item\",\"a [human] item\",\"a loop of more than two items\",\"Claude Code versions other than the one that ran\"]"
  }
}

failed=0
# shellcheck disable=SC2086 # the default list splits on purpose
[ $# -gt 0 ] || set -- $ALL

# Several scenarios: run each in its own process, L3_JOBS at a time, then
# print each one's lines in the order asked; the exit reflects all of them.
l3_child() { L3_CHILD=1 bash "$0" "$1"; }
if [ $# -gt 1 ] && [ "${L3_JOBS:-4}" -gt 1 ] && [ -z "${L3_CHILD:-}" ]; then
  logs=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-logs.XXXXXX")
  pids=() names=() status=0 running=0
  for scenario in "$@"; do
    case " $ALL " in *" $scenario "*) ;; *) echo "unknown scenario $scenario (one of: $ALL)" >&2; exit 2 ;; esac
  done
  # reap: collect the exit of every scenario that ended (bash 3.2 has no wait -n),
  # so a free slot is used at once whichever scenario ended.
  reap() {
    local i
    for ((i = 0; i < ${#pids[@]}; i++)); do
      [ -n "${pids[$i]}" ] && ! kill -0 "${pids[$i]}" 2> /dev/null || continue
      wait "${pids[$i]}" || status=1
      pids[i]="" running=$((running - 1))
    done
  }
  for scenario in "$@"; do
    while [ "$running" -ge "${L3_JOBS:-4}" ]; do reap; [ "$running" -lt "${L3_JOBS:-4}" ] || sleep 1; done
    l3_child "$scenario" > "$logs/$scenario.log" 2>&1 &
    pids+=("$!") names+=("$scenario") running=$((running + 1))
  done
  while [ "$running" -gt 0 ]; do reap; [ "$running" -eq 0 ] || sleep 1; done
  for scenario in "${names[@]}"; do grep -v '^L3 suite:' "$logs/$scenario.log"; done
  rm -rf "$logs"
  [ "$status" -eq 0 ] && echo "L3 suite: all checks passed" || { echo "L3 suite: FAILED"; exit 1; }
  exit 0
fi
for scenario in "$@"; do
  case " $ALL " in *" $scenario "*) ;; *) echo "unknown scenario $scenario (one of: $ALL)" >&2; exit 2 ;; esac
  # Each scenario's result reflects its own checks; the suite's exit, all of them.
  suite_failed=$failed failed=0
  unset -f on_question on_idle done_yet checks idle
  unset L3_STATUSLINE L3_MODE L3_TREE L3_INSTALLED_BIN
  idle() { default_idle; }
  on_question() { return 1; }
  on_idle() { return 1; }
  done_yet() { shipped; }
  "scenario_$scenario" || { failed=1; continue; }
  say "project: $dir"
  if ! l3 start "$scenario" "$dir" > /dev/null; then say "could not start Claude Code"; failed=1; continue; fi
  # As a user would: VBW 2 asks for a reload when it removed VBW 1 command copies.
  if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
  l3 type "$scenario" "$start"
  drive || failed=1
  # Dismiss a pending question with Escape (never answer it), let the session
  # settle, read its cost, then stop. Stop first, then read the state: the result records where the session
  # actually ended, and a stop that acted for the user would show.
  l3 keys "$scenario" Escape; sleep 2; default_idle
  cost_usd=$(read_session_cost)
  l3 stop "$scenario"
  checks
  [ "$suite_failed" -eq 0 ] || failed=1
done
[ "$failed" -eq 0 ] && echo "L3 suite: all checks passed" || { echo "L3 suite: FAILED"; exit 1; }
