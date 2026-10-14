#!/usr/bin/env bash
# Scripted runs of a workflow's closing step (R186, maintainers only; never shipped).
# Evidence level L2: a script drives one headless `claude -p` session per run on a
# practice project; no person uses /vbw:vibe.
#   building   the building workflow on one requirement with one small plan
#   fixing     the fixing workflow on two open fixes (one of a requirement, one of
#              the test command), checks and test files of a few seconds
#   long-fix   the same with checks of about 10 minutes, so vbw fix done runs
#              past one shell command's 10-minute limit
# usage: tools/close-haiku-run.sh building|fixing|long-fix
# Fixture: a practice project built in .vbw/runtime/scratch/close-haiku/<scenario>
# (rebuilt every run; only a folder this tool marked is removed) with this tree's
# plugin/bin/vbw, built the way tools/measure-fix-round.sh builds its project.
# Cost: one Claude Code session with Dev and Lead agents, roughly 0.1 to 0.4 USD
# (the result file holds the session's own figure); long-fix also takes 15+ minutes.
# It uses the Claude login of the user who runs it and writes
# tools/baseline/results/close-haiku/<scenario>.json, read from the session's
# transcripts, the workflow's returned result and the record, never typed by hand.
set -euo pipefail

usage='usage: tools/close-haiku-run.sh building|fixing|long-fix'
case "${1-}" in building | fixing | long-fix) ;; *) echo "$usage" >&2; exit 2 ;; esac
[ $# -eq 1 ] || { echo "$usage" >&2; exit 2; }
scenario="$1"

here="$(cd "$(dirname "$0")/.." && pwd)"
vbw="$here/plugin/bin/vbw"
dir="$here/.vbw/runtime/scratch/close-haiku/$scenario"
result="$here/tools/baseline/results/close-haiku/$scenario.json"
profile=balanced

# Sessions started from inside Claude Code inherit its PATH, whose installed
# plugins' bin/ (an older vbw) would shadow the code under test.
clean=''
IFS=: read -r -a parts <<< "$PATH"
for p in "${parts[@]}"; do
  case "$p" in */plugins/cache/*) ;; *) clean="${clean:+$clean:}$p" ;; esac
done
export PATH="$clean"
# Nothing of the calling session reaches the practice project; the Claude login stays.
unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE CLAUDECODE CLAUDE_CODE_ENTRYPOINT VBW_SESSION_ID
# A headless session stops background tasks 10 minutes after its last turn; long-fix needs the
# workflow to run on until it ends.
export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$dir.gitconfig" LC_ALL=C
mkdir -p "$(dirname "$dir")"

if [ -e "$dir" ]; then
  [ -f "$dir/.close-haiku-run" ] || { echo "vbw: $dir exists and is not a close-haiku-run project; remove it" >&2; exit 1; }
  rm -rf "$dir"
fi
rm -f "$GIT_CONFIG_GLOBAL"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
touch "$dir/.close-haiku-run"
git config --global user.email "close-haiku@example.com"
git config --global user.name "Close Haiku"
git config --global init.defaultBranch main
git config --global gc.auto 0

proj="$dir/project"
mkdir -p "$proj"
cd "$proj"
git init -q
printf 'seed\n' > README.md
git add README.md && git commit -q -m "chore: seed"
"$vbw" init > /dev/null

# ---- the fixture ----
case "$scenario" in
  building)
    fixture='one requirement (R1), one plan (P1.1) that creates src/f1.txt, one check that src/f1.txt holds the word feature'
    mkdir -p src tests
    printf -- '# Practice\n\n## Requirements\n\n- R1 [auto] Feature 1 works: src/f1.txt exists and holds the word feature\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
    "$vbw" spec sync > /dev/null
    printf 'true\n' > tests/all.sh
    printf 'grep -q feature src/f1.txt\n' > tests/f1_1.sh
    printf '{"phases":[{"id":"P1","title":"Feature 1","reqs":["R1"],"tier":"standard"}],"plans":[{"id":"P1.1","phase":"P1","title":"Feature 1","reqs":["R1"],"files":["src/f1.txt"],"tasks":["Create src/f1.txt holding the line: feature 1"]}],"checks":[{"id":"C1","req":"R1","run":["sh","tests/f1_1.sh"],"files":["tests/f1_1.sh"]}]}' | "$vbw" apply > /dev/null
    git add -A && git commit -q -m "feat: planned"
    "$vbw" approve > /dev/null
    ;;
  fixing | long-fix)
    if [ "$scenario" = fixing ]; then
      secs=5
      fixture='two finished requirements with two checks each and two test files of 5 seconds; two open fixes (one of R1, one of the test command) with their changes committed'
      tfiles=2
      timeout=300
    else
      secs=620
      fixture='two finished requirements with one check each of 620 seconds; two open fixes of R1 and R2 with their changes committed (vbw fix done runs about 10.5 minutes)'
      tfiles=0
      timeout=1200
    fi
    mkdir -p src tests
    printf -- '# Practice\n\n## Requirements\n\n- R1 [auto] Feature 1 works\n- R2 [auto] Feature 2 works\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
    if [ "$tfiles" -gt 0 ]; then
      printf '\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' >> .vbw/spec.md
    fi
    "$vbw" spec sync > /dev/null
    printf 'true\n' > tests/all.sh
    printf 'data\n' > src/data.txt
    t=1
    while [ "$t" -le "$tfiles" ]; do
      printf 'sleep %s\ngrep -q . src/data.txt\n' "$secs" > "tests/t_$t.sh"
      t=$((t + 1))
    done
    checks='' cn=0
    for g in 1 2; do
      printf 'feature %s\n' "$g" > "src/f$g.txt"
      for k in 1 2; do
        { [ "$scenario" = long-fix ] && [ "$k" = 2 ]; } && continue
        printf 'sleep %s\ngrep -q . src/f%s.txt\n' "$secs" "$g" > "tests/f${g}_$k.sh"
        cn=$((cn + 1))
        checks="$checks{\"id\":\"C$cn\",\"req\":\"R$g\",\"run\":[\"sh\",\"tests/f${g}_$k.sh\"],\"files\":[\"tests/f${g}_$k.sh\"],\"timeout\":$timeout},"
      done
    done
    printf '{"phases":[{"id":"P1","title":"Feature 1","reqs":["R1"],"tier":"standard"},{"id":"P2","title":"Feature 2","reqs":["R2"],"tier":"standard"}],"plans":[{"id":"P1.1","phase":"P1","title":"Feature 1","reqs":["R1"],"files":["src/f1.txt"]},{"id":"P2.1","phase":"P2","title":"Feature 2","reqs":["R2"],"files":["src/f2.txt"]}],"checks":[%s]}' "${checks%,}" | "$vbw" apply > /dev/null
    git add -A && git commit -q -m "feat: built"
    if [ "$scenario" = fixing ]; then
      fixes='{"id":"F1","req":"R1","attempts":0,"status":"open","note":"group 1"},{"id":"F2","command":"test","attempts":0,"status":"open","note":"group 2"}'
    else
      fixes='{"id":"F1","req":"R1","attempts":0,"status":"open","note":"group 1"},{"id":"F2","req":"R2","attempts":0,"status":"open","note":"group 2"}'
    fi
    jq --argjson f "[$fixes]" '.plans[].status = "done" | .fixes = $f' .vbw/record.json > "$dir/edit.json" && cp "$dir/edit.json" .vbw/record.json
    "$vbw" approve > /dev/null
    printf 'fixed\n' >> src/f1.txt
    git add src/f1.txt && git commit -q -m "fix: group 1"
    if [ "$scenario" = fixing ]; then
      printf 'fixed\n' >> src/data.txt
      git add src/data.txt && git commit -q -m "fix: group 2"
    else
      printf 'fixed\n' >> src/f2.txt
      git add src/f2.txt && git commit -q -m "fix: group 2"
    fi
    ;;
esac
git add -A && git commit -q -m "chore(vbw): fixture" > /dev/null || true

# ---- the run ----
sid=$(uuidgen | tr 'A-Z' 'a-z')
models=$("$vbw" config models)
args_common=$(jq -cn --arg s "$sid" --argjson m "$models" --slurpfile e "$here/plugin/lib/efforts.json" --argjson p "$("$vbw" next --json | jq -c '.profile')" \
  --arg pn "$profile" '{session: $s, models: $m, effort: $e[0][$pn], profile: $p}')
if [ "$scenario" = building ]; then
  wf=building
  VBW_SESSION_ID="$sid" "$vbw" run start build P1.1 > /dev/null
  args=$(printf '%s' "$args_common" | jq -c '. + {plans: ["P1.1"]}')
else
  wf=fixing
  VBW_SESSION_ID="$sid" "$vbw" run start fix F1 F2 > /dev/null
  args=$(printf '%s' "$args_common" | jq -c '. + {groups: [["F1"], ["F2"]]}')
fi
settings='{"enabledPlugins":{"vbw@vbw-marketplace":false},"enableWorkflows":true}'
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ask="Run the VBW $wf workflow now: call the Workflow tool with name vbw:$wf and args $args (a JSON object, not a string). Wait for it to finish, then reply with its returned result as JSON, verbatim."
echo "close-haiku-run: $scenario: session $sid, started $started" >&2
claude -p --model sonnet --permission-mode auto --max-turns 20 --session-id "$sid" --plugin-dir "$here/plugin" \
  --settings "$settings" --allowedTools "Workflow(vbw:$wf)" --output-format json "$ask" < /dev/null > "$dir/session.json" 2> "$dir/session.err" || true
echo "close-haiku-run: session returned" >&2

# ---- the evidence, read from what happened ----
[ -s "$dir/session.json" ] && jq -e '.session_id' "$dir/session.json" > /dev/null || { echo "vbw: the session returned no result; see $dir/session.err" >&2; exit 1; }
# Claude Code keeps its transcripts under the config folder, in a folder named for the project path.
# shellcheck source=tools/resolve-claude-dir.sh
. "$here/tools/resolve-claude-dir.sh"
enc=$(printf '%s' "$proj" | sed 's/[^A-Za-z0-9]/-/g')
wfdir=$(find "$CLAUDE_DIR/projects/$enc/$sid/subagents/workflows" -mindepth 1 -maxdepth 1 -type d 2> /dev/null | head -1)
[ -n "$wfdir" ] || { echo "vbw: no workflow transcripts for session $sid under $CLAUDE_DIR/projects/$enc" >&2; exit 1; }
agent=''
for m in "$wfdir"/agent-*.meta.json; do
  if [ "$(jq -r .description "$m")" = "close run" ]; then agent="$(basename "$m" .meta.json)"; fi
done
[ -n "$agent" ] || { echo "vbw: no 'close run' agent in $wfdir" >&2; exit 1; }
tr="$wfdir/$agent.jsonl"
agent_id="${agent#agent-}"
# What the workflow got back from the closing agent (its journal), not a retelling of it.
answer=$(jq -c --arg id "$agent_id" 'select(.type == "result" and .agentId == $id) | .result' "$wfdir/journal.jsonl" | tail -1)
[ -n "$answer" ] || { echo "vbw: the closing agent returned no result" >&2; exit 1; }
model=$(jq -r 'select(.type == "assistant") | .message.model' "$tr" | head -1)
effort=$(jq -r 'select(.effort != null) | .effort' "$tr" | head -1)
# The shell commands, in order, with when each started.
jq -c 'select(.type == "assistant") | .timestamp as $t | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
  | {cmd: .input.command, at: $t, bg: (.input.run_in_background == true)}' "$tr" > "$dir/commands.jsonl"
# vbw fix done: from its start to the next command; whether Claude Code moved it to the background.
fixdone='{"seconds": null, "backgrounded": false}'
if grep -q 'vbw fix done' "$dir/commands.jsonl"; then
  fixdone=$(jq -cs 'def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    (map(.cmd | test("vbw fix done")) | index(true)) as $i
    | (map(.cmd | test("vbw run confirm")) | index(true)) as $c
    | {seconds: ((.[$c].at | ts) - (.[$i].at | ts)), backgrounded: (.[$i].bg or any(.[]; .bg))}' "$dir/commands.jsonl")
  if [ "$(jq -r .backgrounded <<< "$fixdone")" = false ] && grep -qi 'running in background\|moved to the background\|backgrounded' "$tr"; then
    fixdone=$(jq -c '.backgrounded = true' <<< "$fixdone")
  fi
fi
open_after=$(jq '.lease != null' "$proj/.vbw/record.json")
fixes=$(jq -c '[(.fixes // [])[] | {id, status}]' "$proj/.vbw/record.json")
lead=$(jq -r .lead <<< "$models")
cost=$(jq '.total_cost_usd' "$dir/session.json")
jq -n --arg scenario "$scenario" --arg fixture "$fixture" --arg at "$started" --arg cv "$(claude --version | awk '{print $1}')" \
  --argjson cost "$cost" --arg profile "$profile" --arg lead "$lead" --arg model "$model" --arg effort "$effort" \
  --argjson answer "$answer" --slurpfile cmds "$dir/commands.jsonl" --argjson open "$open_after" --argjson fixes "$fixes" --argjson fd "$fixdone" \
  '{scenario: $scenario, evidence_level: "L2", fixture: $fixture, at: $at, claude_version: $cv, cost_usd: $cost, profile: $profile, lead_model: $lead,
    close: {label: "close run", model: $model, effort_sent: $effort, answer: $answer},
    commands: ($cmds | map(.cmd)), run_open_after: $open, fixes: $fixes, fixdone: $fd,
    not_tested: ["a person using /vbw:vibe (L3)", "the closing step on Haiku in a project of real size", "the other workflows (planning, mapping, verifying)", "Fable as the session model"]}' > "$result"
echo "close-haiku-run: wrote $result" >&2
