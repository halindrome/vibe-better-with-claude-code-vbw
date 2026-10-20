#!/usr/bin/env bats
# R202, phase P163: why M38 and M39 shipped without real-session scenarios, and
# the rule that stops it happening again. The cause is a recorded decision; the
# spec's Constraints state the rule every planner reads; every scenario in
# tools/l3-suite.sh declares the files it covers (a '# covers:' comment line
# right above its function, git pathspecs); tools/l3-stale.sh (also reached as
# bash tools/l3-suite.sh --stale) finds a result older than the newest commit
# of its covered files, or a scenario with no committed result, prints one line
# per stale scenario (its name, the result's date, the newest covering commit)
# and the command to run them, exit 1 when any is stale; bash tools/test.sh
# --release runs it first, on the full path and on the reuse path, and the
# default run, --quick and --lint never do. L1, hermetic: the stale check runs
# on a scratch repository with dated commits; the release runner runs as a copy
# in the fixture of tests/release-reuse-helper.bash with a stand-in stale check
# that logs its call; the repository's own files are read as text.

load helper
load release-reuse-helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
STALE="$REPO_ROOT/tools/l3-stale.sh"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# --- The stale check on a scratch repository.

# dated_commit DATE MESSAGE: commit everything staged at DATE (ISO 8601, UTC).
dated_commit() {
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$FIX" commit -q -m "$2"
}

# result NAME AT: a committed-looking result of NAME written at AT.
result() {
  mkdir -p "$FIX/tools/l3-results"
  jq -n --arg n "$1" --arg at "$2" '{scenario: $n, fixture: "f", cost_usd: 1, evidence_level: "L3", at: $at, passed: true, facts: {}, not_tested: ["x"]}' \
    > "$FIX/tools/l3-results/$1.json"
}

# stale_repo: three scenarios; alpha covers plugin/a.sh (unchanged since its result),
# beta covers plugin/b*.sh (changed after its result), gamma covers plugin/c.sh (no result).
stale_repo() {
  FIX="$TEST_ROOT/fixture repo"
  mkdir -p "$FIX/plugin" "$FIX/tools"
  git -C "$TEST_ROOT" init -q "fixture repo"
  printf 'a\n' > "$FIX/plugin/a.sh"
  printf 'b\n' > "$FIX/plugin/b.sh"
  printf 'c\n' > "$FIX/plugin/c.sh"
  cat > "$FIX/tools/l3-suite.sh" << 'SH'
#!/usr/bin/env bash
ALL="alpha beta gamma"
# covers: plugin/a.sh
scenario_alpha() {
  :
}
# Another comment between the covers line and the function is fine.
# covers: plugin/b*.sh
# The comment block may go on after it.
scenario_beta() {
  :
}
helper() { :; }
# covers: plugin/c.sh
scenario_gamma() {
  :
}
SH
  git -C "$FIX" add -A
  dated_commit 2026-10-01T10:00:00Z "chore: seed"
  printf 'b2\n' > "$FIX/plugin/b.sh"
  git -C "$FIX" add -A
  dated_commit 2026-10-15T10:00:00Z "feat: change b"
  B_COMMIT=$(git -C "$FIX" rev-parse --short HEAD)
  result alpha 2026-10-05T10:00:00Z
  result beta 2026-10-10T10:00:00Z
  export FIX B_COMMIT
}

stale_run() {
  STATUS=0
  OUT=$(bash "$STALE" --repo "$FIX" 2>&1) || STATUS=$?
}

@test "R202: a result older than the newest commit of its covered files is stale, a scenario with no result is stale, a newer result is not; exit 1" {
  [ -f "$STALE" ] || { echo "tools/l3-stale.sh does not exist"; false; }
  stale_repo
  stale_run
  [ "$STATUS" -eq 1 ] || { echo "exit $STATUS: $OUT"; false; }
  printf '%s\n' "$OUT" | grep -q 'beta' || { echo "beta is not reported: $OUT"; false; }
  printf '%s\n' "$OUT" | grep -q 'gamma' || { echo "gamma is not reported: $OUT"; false; }
  ! printf '%s\n' "$OUT" | grep -v '^run:' | grep -q 'alpha' || { echo "alpha (fresh) is reported: $OUT"; false; }
}

@test "R202: each stale line names the scenario, the result's date (or that there is none) and the newest covering commit" {
  stale_repo
  stale_run
  local beta gamma
  beta=$(printf '%s\n' "$OUT" | grep -v '^run:' | grep 'beta')
  gamma=$(printf '%s\n' "$OUT" | grep -v '^run:' | grep 'gamma')
  [ "$(printf '%s\n' "$beta" | grep -c .)" -eq 1 ] || { echo "beta is not one line: $OUT"; false; }
  [ "$(printf '%s\n' "$gamma" | grep -c .)" -eq 1 ] || { echo "gamma is not one line: $OUT"; false; }
  printf '%s' "$beta" | grep -q '2026-10-10' || { echo "beta's line does not name its result's date: $beta"; false; }
  printf '%s' "$beta" | grep -q "$B_COMMIT" || { echo "beta's line does not name the commit $B_COMMIT that changed plugin/b.sh: $beta"; false; }
  printf '%s' "$beta" | grep -q '2026-10-15' || { echo "beta's line does not name the commit's date: $beta"; false; }
  printf '%s' "$gamma" | grep -qi 'no result' || { echo "gamma's line does not say it has no result: $gamma"; false; }
}

@test "R202: the stale check ends with the command to run the stale scenarios, in the suite's order" {
  stale_repo
  stale_run
  printf '%s\n' "$OUT" | tail -n 1 | grep -q 'bash tools/l3-suite.sh beta gamma' || { echo "the last line is not the command to run them: $OUT"; false; }
}

@test "R202: with every result newer than its covered files' newest commit nothing is stale and the exit is 0" {
  stale_repo
  result beta 2026-10-20T10:00:00Z
  result gamma 2026-10-20T10:00:00Z
  stale_run
  [ "$STATUS" -eq 0 ] || { echo "exit $STATUS: $OUT"; false; }
  ! printf '%s\n' "$OUT" | grep -qE '^(stale|run):' || { echo "something is reported stale: $OUT"; false; }
}

@test "R202: the stale check runs under bash 3.2 rules: no mapfile, readarray, associative arrays, eval or bash -c with data" {
  [ -f "$STALE" ] || { echo "tools/l3-stale.sh does not exist"; false; }
  ! grep -nE 'mapfile|readarray|declare -A|\beval\b|bash -c "\$' "$STALE" || { echo "a bash 4 feature or data run as code in tools/l3-stale.sh"; false; }
  head -n 1 "$STALE" | grep -q '^#!/usr/bin/env bash' || { echo "no bash shebang"; false; }
}

# --- The release runner calls it first; the ordinary runs never do.

# stale_stub: a stand-in tools/l3-stale.sh in the fake repository that logs its call
# and exits STALE_FAIL (default 0), committed and proved so the reuse path still holds.
stale_stub() {
  printf '#!/usr/bin/env bash\necho l3-stale >> "$LOG"\necho "stale: x"\nexit "${STALE_FAIL:-0}"\n' > "$FAKE/tools/l3-stale.sh"
  (cd "$FAKE" && git add -A && git commit -q -m "chore(test): stale stand-in")
  prove_with '{full: true, passed: true}'
}

# first_of WORD: the line number of WORD's first call in the log, or 9999 when it never ran.
first_of() { grep -n "^$1" "$LOG" | head -n 1 | cut -d: -f1 | grep . || echo 9999; }

@test "R202: bash tools/test.sh --release on the reuse path runs the stale check before anything else" {
  fake_repo
  stale_stub
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "exit $CODE: $OUT"; false; }
  reused
  grep -qx 'l3-stale' "$LOG" || { echo "the stale check did not run:"; cat "$LOG"; false; }
  [ "$(first_of l3-stale)" -lt "$(first_of bench-hooks)" ] || { echo "the stale check did not run first:"; cat "$LOG"; false; }
}

@test "R202: bash tools/test.sh --release on the full path runs the stale check before the test files" {
  fake_repo
  stale_stub
  printf 'more\n' >> "$FAKE/src/app.txt"
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "exit $CODE: $OUT"; false; }
  everything
  grep -qx 'l3-stale' "$LOG" || { echo "the stale check did not run:"; cat "$LOG"; false; }
  [ "$(first_of l3-stale)" -lt "$(first_of bats)" ] || { echo "the stale check did not run before the test files:"; cat "$LOG"; false; }
}

@test "R202: a stale scenario fails the release run before any test file runs, naming it" {
  fake_repo
  stale_stub
  STALE_FAIL=1 fake_run --release
  [ "$CODE" -ne 0 ] || { echo "the release run passed with a stale scenario: $OUT"; false; }
  [ -z "$(bats_calls)" ] || { echo "test files ran after the stale check failed:"; cat "$LOG"; false; }
  [[ "$OUT" == *"stale: x"* ]] || { echo "the stale scenario is not named: $OUT"; false; }
}

@test "R202: the default run, --quick and --lint never run the stale check" {
  fake_repo
  stale_stub
  local mode
  for mode in "" --quick --lint; do
    # shellcheck disable=SC2086 # an empty mode is the default run
    fake_run $mode
    [ "$CODE" -eq 0 ] || { echo "exit $CODE for '$mode': $OUT"; false; }
    ! grep -qx 'l3-stale' "$LOG" || { echo "the stale check ran for '$mode':"; cat "$LOG"; false; }
  done
}

@test "R202: CI's shard 1 runs the stale check first, as the release run does; the other shards do not" {
  fake_repo
  stale_stub
  fake_run --shard 1/4
  [ "$CODE" -eq 0 ] || { echo "exit $CODE: $OUT"; false; }
  grep -qx 'l3-stale' "$LOG" || { echo "shard 1 did not run the stale check:"; cat "$LOG"; false; }
  [ "$(first_of l3-stale)" -lt "$(first_of shellcheck)" ] || { echo "shard 1 did not run it first:"; cat "$LOG"; false; }
  fake_run --shard 2/4
  ! grep -qx 'l3-stale' "$LOG" || { echo "shard 2 ran the stale check:"; cat "$LOG"; false; }
}

# --- The real suite: covers lines, the --stale way in, the header.

all_scenarios() { grep -E '^ALL=' "$SUITE" | sed 's/^ALL="//; s/"$//' | tr ' ' '\n' | grep .; }

# covers_of NAME: the pathspecs of NAME's covers line (the nearest '# covers:' line
# above scenario_NAME() with only comment lines between), one per line.
covers_of() {
  awk -v name="$1" '
    /^# covers:/ { c = $0; sub(/^# covers:[ \t]*/, "", c) }
    /^scenario_[A-Za-z0-9_-]+\(\)/ { n = $0; sub(/\(\).*/, "", n); sub(/^scenario_/, "", n); if (n == name) { print c; exit } }
    !/^#/ { c = "" }' "$SUITE" | tr ' ' '\n' | grep .
}

@test "R202: every scenario in ALL declares the files it covers, and each pathspec matches a tracked file" {
  local s p n
  for s in $(all_scenarios); do
    n=$(covers_of "$s" | grep -c .)
    [ "$n" -gt 0 ] || { echo "scenario $s has no '# covers:' line above scenario_$s()"; false; }
    while IFS= read -r p; do
      [ -n "$(git -C "$REPO_ROOT" ls-files -- "$p")" ] || { echo "scenario $s covers '$p', which matches no tracked file"; false; }
    done <<< "$(covers_of "$s")"
  done
}

@test "R202: the sessions scenario covers the M38 files; ownrules and ownfix cover the M39 files" {
  local f have
  have=$(covers_of sessions)
  for f in plugin/lib/sessions.sh plugin/lib/holder.jq plugin/lib/cmd-run.sh plugin/lib/cmd-next.sh plugin/lib/next.jq \
    plugin/scripts/statusline.jq plugin/hooks/panel-sessions.js plugin/hooks/panel-pane.js plugin/skills/vibe/SKILL.md; do
    printf '%s\n' "$have" | grep -qxF "$f" || { echo "sessions does not cover $f: $have"; false; }
  done
  have=$(printf '%s\n%s\n' "$(covers_of ownrules)" "$(covers_of ownfix)")
  for f in plugin/lib/cmd-mutate.sh plugin/lib/cmd-commit.sh plugin/lib/cmd-fix.sh plugin/lib/cmd-check.sh plugin/lib/checks.sh \
    plugin/lib/cmd-show.sh plugin/lib/failing-tests.jq plugin/workflows/fixing.js plugin/agents/dev.md; do
    printf '%s\n' "$have" | grep -qxF "$f" || { echo "neither ownrules nor ownfix covers $f: $have"; false; }
  done
}

@test "R202: bash tools/l3-suite.sh --stale is the stale check, starts no Claude Code, and the header names the covers lines and --stale" {
  grep -q -- '--stale' "$SUITE" || { echo "tools/l3-suite.sh has no --stale"; false; }
  grep -q 'l3-stale.sh' "$SUITE" || { echo "tools/l3-suite.sh --stale does not run tools/l3-stale.sh"; false; }
  sed -n '1,30p' "$SUITE" | grep -q 'covers:' || { echo "the header does not name the covers lines"; false; }
  sed -n '1,30p' "$SUITE" | grep -q -- '--stale' || { echo "the header does not name --stale"; false; }
  run bash "$SUITE" --stale
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || { echo "exit $status: $output"; false; }
  [[ "$output" != *"could not start Claude Code"* ]] || { echo "--stale tried to start Claude Code"; false; }
  [[ "$output" == *"run: bash tools/l3-suite.sh"* || "$output" == *"no stale"* ]] || { echo "neither a run line nor 'no stale': $output"; false; }
}

# --- The cause, the rule and the rulebook.

@test "R202: the cause of the missing scenarios is a recorded decision with its evidence and what P163 changes" {
  local d
  d=$(jq -r '[.decisions[] | select((.text + " " + (.why // "")) | test("P152") and test("P157") and test("scenario"))] | last // empty | .text + " " + (.why // "")' "$REPO_ROOT/.vbw/record.json")
  [ -n "$d" ] || { echo "no decision names P152 to P157 and the scenarios"; false; }
  printf '%s' "$d" | grep -q 'P148' || { echo "the decision does not name P148 (a phase whose criteria asked for a scenario): $d"; false; }
  printf '%s' "$d" | grep -q 'D95' || { echo "the decision does not name D95: $d"; false; }
  printf '%s' "$d" | grep -q 'test.sh' || { echo "the decision does not name tools/test.sh --release knowing nothing of scenarios: $d"; false; }
  printf '%s' "$d" | grep -qi 'constraint' || { echo "the decision does not name the spec constraint P163 adds: $d"; false; }
  printf '%s' "$d" | grep -qi 'stale' || { echo "the decision does not name the stale check P163 adds: $d"; false; }
}

constraints() { awk '/^## Constraints/ { on = 1; next } on && /^## / { exit } on { print }' "$REPO_ROOT/.vbw/spec.md"; }

@test "R202: the spec's Constraints state the scenario rule every planner reads, and the spec's requirements are in step with the record" {
  local c
  c=$(constraints | grep -v '^[[:space:]]*$')
  [ -n "$c" ] || { echo ".vbw/spec.md has an empty Constraints section"; false; }
  printf '%s' "$c" | grep -q 'tools/l3-suite.sh' || { echo "the constraint does not name tools/l3-suite.sh: $c"; false; }
  printf '%s' "$c" | grep -q 'tools/l3-results' || { echo "the constraint does not name tools/l3-results: $c"; false; }
  printf '%s' "$c" | grep -qi 'real' && printf '%s' "$c" | grep -qi 'scenario' || { echo "the constraint does not speak of a real-user scenario: $c"; false; }
  printf '%s' "$c" | grep -qi 'milestone' || { echo "the constraint does not bind the milestone: $c"; false; }
  printf '%s' "$c" | grep -qi 'stale' || { echo "the constraint does not say an old result is stale: $c"; false; }
  local line
  while IFS= read -r line; do
    grep -qxF -- "$line" "$REPO_ROOT/.vbw/spec.md" || { echo "the record's requirement is not in the spec: $line"; false; }
  done <<< "$(jq -r '.requirements[] | "- \(.id) [\(.proof)] \(.text)"' "$REPO_ROOT/.vbw/record.json")"
}

@test "R202: CLAUDE.md and AGENTS.md keep one Testing paragraph on real-user scenarios, naming the covers lines and --stale" {
  local a b
  a=$(grep -E '^- \*\*Real-user scenarios\*\*' "$REPO_ROOT/CLAUDE.md")
  b=$(grep -E '^- \*\*Real-user scenarios\*\*' "$REPO_ROOT/AGENTS.md")
  [ -n "$a" ] && [ -n "$b" ] || { echo "a Real-user scenarios paragraph is missing"; false; }
  [ "$a" = "$b" ] || { echo "CLAUDE.md and AGENTS.md differ on the paragraph"; false; }
  printf '%s' "$a" | grep -q 'covers:' || { echo "the paragraph does not name the covers lines: $a"; false; }
  printf '%s' "$a" | grep -q -- '--stale' || { echo "the paragraph does not name --stale: $a"; false; }
}
