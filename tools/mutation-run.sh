#!/usr/bin/env bash
# Scripted runs of the mutation check (R188, maintainers only; never shipped).
# Evidence level L2: a script drives one headless `claude -p` session per run on a
# practice project; no person uses /vbw:vibe.
#   standard   the building workflow at the standard tier: the Dev breaks its code once
#              per rule with vbw mutate
#   express    the same project and plan at the express tier: no mutation step
# usage: tools/mutation-run.sh standard|express
# Fixture: a practice project built in .vbw/runtime/scratch/mutation/<scenario> (rebuilt
# every run; only a folder this tool marked is removed) with this tree's plugin/bin/vbw,
# built the way tools/close-haiku-run.sh builds its project: one plan, two [auto]
# requirements with one rule each (R1: hello.sh prints hello; R2: bye.sh prints bye), the
# check of R2 an approved test that cannot fail on what bye.sh prints, the contract
# approved, the phase forced to the scenario's tier.
# Cost: one Claude Code session with a Dev and a Lead agent, a few USD at most (the result
# file holds the session's own figure). It uses the Claude login of the user who runs it
# and writes tools/baseline/results/mutation/<scenario>.json, read from the record, vbw
# next and the session's transcripts, never typed by hand. The decision that records the
# result (vbw decide) is made afterwards and its id written into the file with jq.
set -euo pipefail

usage='usage: tools/mutation-run.sh standard|express'
case "${1-}" in standard | express) ;; *) echo "$usage" >&2; exit 2 ;; esac
[ $# -eq 1 ] || { echo "$usage" >&2; exit 2; }
scenario="$1"

here="$(cd "$(dirname "$0")/.." && pwd)"
vbw="$here/plugin/bin/vbw"
dir="$here/.vbw/runtime/scratch/mutation/$scenario"
result="$here/tools/baseline/results/mutation/$scenario.json"
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
# A headless session stops background tasks 10 minutes after its last turn; the build runs on until it ends.
export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$dir.gitconfig" LC_ALL=C
mkdir -p "$(dirname "$dir")" "$(dirname "$result")"

if [ -e "$dir" ]; then
  [ -f "$dir/.mutation-run" ] || { echo "vbw: $dir exists and is not a mutation-run project; remove it" >&2; exit 1; }
  rm -rf "$dir"
fi
rm -f "$GIT_CONFIG_GLOBAL"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
touch "$dir/.mutation-run"
git config --global user.email "mutation-run@example.com"
git config --global user.name "Mutation Run"
git config --global init.defaultBranch main
git config --global gc.auto 0

proj="$dir/project"
mkdir -p "$proj"
cd "$proj"
git init -q
printf 'seed\n' > README.md
git add README.md && git commit -q -m "chore: seed"
"$vbw" init > /dev/null

# ---- the fixture (the same for both scenarios; only the tier differs) ----
fixture='one plan (P1.1) creating src/hello.sh and src/bye.sh; R1 (hello.sh prints hello) and R2 (bye.sh prints bye), one rule each; the check of R2 only runs bye.sh and cannot fail on what it prints'
mkdir -p src tests
printf -- '# Practice\n\n## Requirements\n\n- R1 [auto] Greeting: src/hello.sh prints hello\n- R2 [auto] Farewell: src/bye.sh prints bye\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
"$vbw" spec sync > /dev/null
"$vbw" config rigor "$scenario" > /dev/null
printf 'true\n' > tests/all.sh
printf '[ "$(sh src/hello.sh)" = hello ]\n' > tests/hello.sh
printf 'sh src/bye.sh > /dev/null\n' > tests/bye.sh
jq -nc --arg t "$scenario" '{phases: [{id: "P1", title: "Greetings", reqs: ["R1", "R2"], tier: $t}],
  plans: [{id: "P1.1", phase: "P1", title: "Greetings", reqs: ["R1", "R2"], files: ["src/hello.sh", "src/bye.sh"],
    tasks: ["Create src/hello.sh: a shell script that prints hello", "Create src/bye.sh: a shell script that prints bye"]}],
  checks: [{id: "C1", req: "R1", run: ["sh", "tests/hello.sh"], files: ["tests/hello.sh"]},
           {id: "C2", req: "R2", run: ["sh", "tests/bye.sh"], files: ["tests/bye.sh"]}],
  rules: [{req: "R1", text: "hello.sh prints hello", check: "C1"}, {req: "R2", text: "bye.sh prints bye", check: "C2"}]}' | "$vbw" apply > /dev/null
git add -A && git commit -q -m "feat: planned"
"$vbw" approve > /dev/null
git add -A && git commit -q -m "chore(vbw): fixture" > /dev/null || true
[ "$("$vbw" next --json | jq -r '.rigor.P1.tier')" = "$scenario" ] || { echo "vbw: the phase is not at the $scenario tier" >&2; exit 1; }

# ---- the run ----
sid=$(uuidgen | tr 'A-Z' 'a-z')
models=$("$vbw" config models)
nextdoc=$("$vbw" next --json)
args=$(jq -cn --arg s "$sid" --argjson m "$models" --slurpfile e "$here/plugin/lib/efforts.json" --argjson n "$nextdoc" --arg pn "$profile" \
  '{session: $s, models: $m, effort: $e[0][$pn], profile: $n.profile, rigor: $n.rigor, plans: ["P1.1"]}')
VBW_SESSION_ID="$sid" "$vbw" run start build P1.1 > /dev/null
settings='{"enabledPlugins":{"vbw@vbw-marketplace":false},"enableWorkflows":true}'
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
t0=$(date +%s)
ask="Run the VBW building workflow now: call the Workflow tool with name vbw:building and args $args (a JSON object, not a string). Wait for it to finish, then reply with its returned result as JSON, verbatim."
echo "mutation-run: $scenario: session $sid, started $started" >&2
claude -p --model sonnet --permission-mode auto --max-turns 20 --session-id "$sid" --plugin-dir "$here/plugin" \
  --settings "$settings" --allowedTools "Workflow(vbw:building)" --output-format json "$ask" < /dev/null > "$dir/session.json" 2> "$dir/session.err" || true
t1=$(date +%s)
echo "mutation-run: session returned" >&2

# ---- the evidence, read from what happened ----
[ -s "$dir/session.json" ] && jq -e '.session_id' "$dir/session.json" > /dev/null || { echo "vbw: the session returned no result; see $dir/session.err" >&2; exit 1; }
# vbw next before any proof: what the build left to ask.
"$vbw" next --json > "$dir/next.json"
# shellcheck source=tools/resolve-claude-dir.sh
. "$here/tools/resolve-claude-dir.sh"
enc=$(printf '%s' "$proj" | sed 's/[^A-Za-z0-9]/-/g')
wfdir=$(find "$CLAUDE_DIR/projects/$enc/$sid/subagents/workflows" -mindepth 1 -maxdepth 1 -type d 2> /dev/null | head -1)
[ -n "$wfdir" ] || { echo "vbw: no workflow transcripts for session $sid under $CLAUDE_DIR/projects/$enc" >&2; exit 1; }
agent=''
for m in "$wfdir"/agent-*.meta.json; do
  if [ "$(jq -r .description "$m")" = "dev P1.1" ]; then agent="$(basename "$m" .meta.json)"; fi
done
[ -n "$agent" ] || { echo "vbw: no 'dev P1.1' agent in $wfdir" >&2; exit 1; }
# The Dev's shell commands, in order, with when each started.
jq -c 'select(.type == "assistant") | .timestamp as $t | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
  | {cmd: .input.command, at: $t}' "$wfdir/$agent.jsonl" > "$dir/commands.jsonl"
# The mutation step: from its first vbw mutate to the vbw plan done that follows it; none when there is no vbw mutate.
added=$(jq -cs 'def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  (map(.cmd | test("vbw mutate")) | index(true)) as $m
  | (map(.cmd | test("vbw plan done")) | rindex(true)) as $d
  | if $m == null or $d == null then 0 else ((.[$d].at | ts) - (.[$m].at | ts)) / 60 end' "$dir/commands.jsonl")
rec="$proj/.vbw/record.json"
cost=$(jq '.total_cost_usd' "$dir/session.json")
jq -n --arg scenario "$scenario" --arg fixture "$fixture" --arg at "$started" --arg cv "$(claude --version | awk '{print $1}')" \
  --argjson cost "$cost" --argjson minutes "$(( (t1 - t0) * 10 / 60 ))" --argjson added "$added" \
  --slurpfile rec "$rec" --slurpfile nx "$dir/next.json" --slurpfile cmds "$dir/commands.jsonl" '
  ($rec[0].plans[] | select(.id == "P1.1")) as $p
  | {scenario: $scenario, tier: $rec[0].phases[0].tier, evidence_level: "L2", fixture: $fixture, at: $at, claude_version: $cv,
     cost_usd: $cost, minutes: ($minutes / 10), minutes_added: $added, decision: null,
     weak_rule: {req: "R2", text: "bye.sh prints bye"},
     mutations: ($p.mutations // []), next_after_build: {action: $nx[0].action, files: ($nx[0].detail.files // $nx[0].files // [])},
     plan_status: $p.status, commands: ($cmds | map(.cmd)),
     not_tested: ["a person using /vbw:vibe (L3)", "a project of real size", "the deep tier", "models other than Sonnet for the Dev"]}' > "$result"
echo "mutation-run: wrote $result" >&2
