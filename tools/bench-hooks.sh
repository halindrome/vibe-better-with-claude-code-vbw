#!/usr/bin/env bash
# Hook cost budget (build plan M3, K20): the PreToolUse guard runs before
# every tool call. Runs the hooks.json command the way Claude Code does (sh -c,
# JSON on stdin, CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR set) and measures the
# CPU time (user + system) of the whole process tree per call, averaged over
# RUNS calls. VBW's own cost is the hook's CPU time minus that of the same
# `sh -c jq` with an empty program: shell and jq startup are the platform's
# (about 8 ms of CPU on an idle Mac), paid by any hook, and not ours to remove.
# The budget (R151): VBW's own CPU per call is at most VBW_HOOK_BUDGET_MS (default 20),
# judged for each guard alone, however it compares with the startup.
# - CPU time, not wall-clock time: waiting for a busy machine is not the hook's
#   work.
# - A machine too busy to measure: when that startup alone (measured first) is above
#   the hook limit, the bench prints one line saying so, judges nothing and exits 0.
# A real regression still shows: an added subprocess costs several ms, and the 20 KB
# heredoc case catches work that grows faster than the input.
# Every input is measured on the small record, on a record of more than 2 MB
# (R149: a long-lived project's record) and on the records of N checks below,
# all with the same build lease.
# The status line is measured on both records too: its CPU per call is at most
# VBW_STATUSLINE_BUDGET_MS (default 60), startup included.
# Three more projects (R150) hold records of 51, 500 and 2,000 checks (the last over
# 2 MB), each written once by the kernel, so each is schema 4 with the protected
# field. The small record is format 4 too. Every guard input takes the path a real
# project takes, and the lines 'guard (NAME, N checks)' share one budget: a guard's
# cost does not climb with the number of checks.
# VBW_BENCH_RUNS and VBW_BENCH_PLUGIN_ROOT override the runs and the plugin (tests).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET_MS="${VBW_HOOK_BUDGET_MS:-20}"
STATUS_MS="${VBW_STATUSLINE_BUDGET_MS:-60}"
RUNS="${VBW_BENCH_RUNS:-100}"
PLUGIN="${VBW_BENCH_PLUGIN_ROOT:-$ROOT/plugin}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# A step that fails under set -e says where, instead of ending the bench silently.
trap 'echo "bench-hooks: stopped at line $LINENO (status $?)" >&2' ERR
hooks_json="$PLUGIN/hooks/hooks.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$work"

# cpu_pair INPUT BASELINE HOOK: the mean CPU time in ms of RUNS runs of each
# `sh -c` command, "BASELINE HOOK", alternating call by call so both see the
# same machine. The children's user and system time comes from bash's `times`
# (millisecond resolution), written to a file to stay in this shell.
cpu_pair() {
  local i c log="$work/times.log"
  : > "$log"
  for ((i = 0; i < RUNS; i++)); do
    for c in "$2" "$3"; do
      times >> "$log"
      sh -c "$c" < "$1" > /dev/null 2>&1 || true
      times >> "$log"
    done
  done
  # Each `times` prints the shell's line, then the children's cumulative line.
  awk -v runs="$RUNS" '
    function sec(s) { sub(/s$/, "", s); split(s, p, "m"); return p[1] * 60 + p[2] }
    NR % 2 == 0 { t[++n] = sec($1) + sec($2) }
    END { for (k = 1; k + 1 <= n; k += 2) sum[int((k - 1) / 2) % 2] += t[k + 1] - t[k]
          printf "%.1f %.1f\n", sum[0] * 1000 / runs, sum[1] * 1000 / runs }' "$log"
}

# Measure the platform's sh and jq startup first, before the test records are
# built: above the hook limit, the machine is too busy to judge anything.
read -r startup _ < <(cpu_pair /dev/null "jq -n empty" "jq -n empty")
if perl -e 'exit($ARGV[0] > $ARGV[1] ? 0 : 1)' -- "$startup" "$BUDGET_MS"; then
  printf 'machine too busy to measure: sh and jq startup takes %s ms CPU per call, above the %s ms hook limit; nothing judged\n' "$startup" "$BUDGET_MS"
  exit 0
fi

git -C "$work" init -q
mkdir -p "$work/.vbw"
# A build lease on the record: the interp case is a build agent's command, which
# the guard reads in full. Calls without an agent_type are never held to it.
jq -nc --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema: 4, lease: {run: "build-1", kind: "build", session: "bench", started_at: $t, files: ["src/pay.py"]}, protected: [], checks: []}' > "$work/.vbw/record.json"

# Representative calls: a compound command the guard must read in full (git, a
# heredoc, quotes, a substitution), one it can skip unread, and a file read, and a build agent's program command.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command:
  "git status && npm test -- --watch=false 2>&1 | tail -20; cat <<EOF > notes.md\nhello \"world\" $(date)\nEOF"}}' > "$work/git.json"
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command: "npm test -- --watch=false 2>&1 | tail -20"}}' > "$work/npm.json"
big=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "line %d with \"quotes\" and $(cmd) and git words\n", i }')
jq -nc --arg d "$work" --arg b "$big" '{tool_name: "Bash", cwd: $d, tool_input: {command: ("git add notes.md && cat > notes.md <<'\''EOF'\''\n" + $b + "EOF")}}' > "$work/big.json"
# A build agent running Python from a heredoc on a build lease: the program is read for the files it writes.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, session_id: "bench", agent_id: "x1", agent_type: "workflow-subagent", tool_input: {command:
  "python3 - <<'\''EOF'\''\nimport json\nwith open(\"src/pay.py\", \"w\") as f:\n    json.dump({\"paid\": True}, f)\nprint(open(\"src/pay.py\").read())\nEOF"}}' > "$work/interp.json"
jq -nc --arg d "$work" '{tool_name: "Read", cwd: $d, tool_input: {file_path: ($d + "/src/app.js")}}' > "$work/read.json"
# An answered question unrelated to approval: the PostToolUse hook runs after
# every AskUserQuestion and must stay cheap when the answer is not an approval.
jq -nc --arg d "$work" '{hook_event_name: "PostToolUse", tool_name: "AskUserQuestion", cwd: $d,
  tool_input: {questions: [{question: "Which database should the app use?", options: [{label: "SQLite"}, {label: "Postgres"}]}]},
  tool_response: {answers: {"Which database should the app use?": "SQLite"}}}' > "$work/answer.json"

# The large project: a record of more than 2 MB in its own folder, the same build
# lease plus a long history (requirements with rules, checks, phases, plans and
# decisions of a shipped milestone, every text padded), keys in the writer's
# order (schema, lease, protected, checks, then the rest). The kernel then rewrites it once
# (vbw decide, a record write), so the file holds the format the kernel writes:
# schema 4 with the protected field, which the guards read without walking the checks.
large="$work/large"
mkdir -p "$large"
git -C "$large" init -q
(cd "$large" && "$PLUGIN/bin/vbw" init > /dev/null)
jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  ("~" * 5000) as $f
  | "2026-01-01T00:00:00Z" as $at
  | [range(1; 51)] as $n
  | .lease = {run: "build-1", kind: "build", session: "bench", started_at: $t, files: ["src/pay.py"]}
  | .milestone = {id: "M2", title: "New work", status: "active"}
  | .shipped = [{id: "M1", title: "Old work", at: $at}]
  | .requirements = [$n[] | {id: "R\(.)", text: ("Old part \(.) works" + $f), proof: "auto", status: "proven", milestone: "M1",
                              rules: [{text: ("Old rule \(.)" + $f), check: "C\(2 * . - 1)"}, {text: "Old second rule \(.)", check: "C\(2 * .)"}]}]
  | .checks = [$n[] | {id: "C\(2 * . - 1)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]},
                      {id: "C\(2 * .)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}]
  | .phases = [$n[] | {id: "P\(.)", title: "Old phase \(.)", reqs: ["R\(.)"], milestone: "M1",
                        goal: ("Old goal \(.)" + $f), criteria: [("Old criterion \(.)" + $f)], tier: "standard",
                        qa: {result: "pass", tier: "standard", tree: "0000000000000000000000000000000000000000", at: $at}}]
  | .plans = [$n[] as $k | (1, 2) | {id: "P\($k).\(.)", phase: "P\($k)", title: "Old plan \($k).\(.)", reqs: ["R\($k)"],
                                      files: ["src/old/\($k)-\(.).txt"], after: [], status: "done", role: "dev",
                                      tasks: [("Old task \($k).\(.)" + $f)]}]
  | .decisions = [range(1; 121) | {id: "D\(.)", text: ("Old decision \(.)" + $f), at: $at}]
                 + [{id: "D121", text: ("Old long decision" + ("~" * 140000)), at: $at}]
  | .protected = ["tests/old.sh"]
  | {schema, lease, protected, checks} + .' \
  "$large/.vbw/record.json" > "$large/.vbw/edited.json"
cat "$large/.vbw/edited.json" > "$large/.vbw/record.json"
rm -f "$large/.vbw/edited.json"
(cd "$large" && "$PLUGIN/bin/vbw" decide "Benchmark record written by the kernel" > /dev/null)
printf 'large record: %s bytes\n' "$(wc -c < "$large/.vbw/record.json" | tr -d ' ')"

# sized N: a project of N checks (one per requirement) in $work/checks-N, its
# history padded in proportion, written once by the kernel (vbw decide).
sized() {
  local n="$1" d="$work/checks-$1"
  mkdir -p "$d"
  git -C "$d" init -q
  (cd "$d" && "$PLUGIN/bin/vbw" init > /dev/null)
  jq --argjson n "$n" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    "2026-01-01T00:00:00Z" as $at
    | [range(1; $n + 1)] as $k
    | .lease = {run: "build-1", kind: "build", session: "bench", started_at: $t, files: ["src/pay.py"]}
    | .milestone = {id: "M2", title: "New work", status: "active"}
    | .shipped = [{id: "M1", title: "Old work", at: $at}]
    | .requirements = [$k[] | {id: "R\(.)", text: "Old part \(.) works", proof: "auto", status: "proven", milestone: "M1",
                                rules: [{text: "Old rule \(.)", check: "C\(.)"}]}]
    | .checks = [$k[] | {id: "C\(.)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}]
    | .decisions = [{id: "D1", text: ("Old long decision" + ("~" * ($n * 1100))), at: $at}]
    | .protected = ["tests/old.sh"]
    | {schema, lease, protected, checks} + .' "$d/.vbw/record.json" > "$d/.vbw/edited.json"
  cat "$d/.vbw/edited.json" > "$d/.vbw/record.json"
  rm -f "$d/.vbw/edited.json"
  (cd "$d" && "$PLUGIN/bin/vbw" decide "Benchmark record written by the kernel" > /dev/null)
  printf 'record (%s checks): %s bytes, schema %s\n' "$n" "$(wc -c < "$d/.vbw/record.json" | tr -d ' ')" "$(jq -r .schema "$d/.vbw/record.json")"
}
for n in 51 500 2000; do sized "$n"; done

# guards DIR LABEL: measure every input against the project at DIR; LABEL is
# the empty string, or ", large record".
status=0
guards() {
  local dir="$1" label="$2" input tool event hook shell total own line baseline file
  export CLAUDE_PROJECT_DIR="$dir"
  baseline="jq -nc 'input | empty' - \"$dir/.vbw/record.json\" \"$CLAUDE_PLUGIN_ROOT/hooks/end.json\" 2>/dev/null || true"
  for input in git npm big interp read answer; do
    tool=$(jq -r .tool_name "$work/$input.json")
    event=PreToolUse
    [ "$input" != answer ] || event=PostToolUse
    hook=$(jq -r --arg t "$tool" --arg e "$event" '[.hooks[$e][] | select(.matcher as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$hooks_json")
    file="$work/$input.json"
    if [ "$dir" != "$work" ]; then
      file="$work/$input.large.json"
      jq -c --arg o "$work" --arg d "$dir" 'walk(if type == "string" and startswith($o) then $d + .[($o | length):] else . end)' \
        "$work/$input.json" > "$file"
    fi
    read -r shell total < <(cpu_pair "$file" "$baseline" "$hook")
    own=$(perl -e 'printf "%.1f", $ARGV[0] - $ARGV[1]' -- "$total" "$shell")
    line=$(printf 'guard (%s%s): %s ms own CPU per call (sh and jq startup %s ms); budget %s ms' \
      "$input" "$label" "$own" "$shell" "$BUDGET_MS")
    if perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$own" "$BUDGET_MS"; then
      printf '%s\n' "$line"
    else
      printf '%s: OVER\n' "$line" >&2
      status=1
    fi
  done
}

# statusline DIR LABEL: the status line's CPU per call (the whole process tree,
# startup included) for a session in the project at DIR.
statusline() {
  local dir="$1" label="$2" cmd total line
  jq -nc --arg d "$dir" '{session_id: "bench", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"}}' > "$work/statusline.json"
  cmd="NO_COLOR=1 bash '$PLUGIN/scripts/vbw-statusline.sh'"
  read -r _ total < <(cpu_pair "$work/statusline.json" true "$cmd")
  line=$(printf 'status line%s: %s ms CPU per call; budget %s ms' "$label" "$total" "$STATUS_MS")
  if perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$total" "$STATUS_MS"; then
    printf '%s\n' "$line"
  else
    printf '%s: OVER\n' "$line" >&2
    status=1
  fi
}

guards "$work" ""
guards "$large" ", large record"
for n in 51 500 2000; do guards "$work/checks-$n" ", $n checks"; done
statusline "$work" ""
statusline "$large" " (large record)"
exit $status
