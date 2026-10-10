#!/usr/bin/env bats
# R164 (CLAUDE.md testing, docs/proof.md): before a push, bash tools/test.sh
# --release reuses the last full proof (a vbw prove that ran the whole suite,
# recorded in .vbw/record.json) when it passed on code that differs from the
# working tree only in the four version files (VERSION,
# plugin/.claude-plugin/plugin.json, .claude-plugin/marketplace.json,
# marketplace.json) and CHANGELOG.md: it then runs only the timed speed checks
# and the benchmarks, and prints which proof it reused. When any other file
# differs (uncommitted changes included), when there is no passing full proof,
# or when the last full proof failed, it runs everything and prints why. A
# partial proof never counts as full. Failing timed checks or benchmarks still
# fail the run, and the CI shards behave as before. L1: a copy of tools/test.sh
# and of the plugin runs in a scratch git repository whose bats, shellcheck,
# parallel, node, getconf and benchmarks are stand-ins that log their calls.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# fake_repo: the scratch repository, committed, with a passing full proof of
# its current code in .vbw/record.json (AT is the proof's time).
fake_repo() {
  FAKE="$TEST_ROOT/fake repo"
  LOG="$TEST_ROOT/calls.log"
  STUBS="$TEST_ROOT/stubs"
  AT="2026-10-10T10:00:00Z"
  export FAKE LOG STUBS AT
  mkdir -p "$FAKE/tools" "$FAKE/tests" "$FAKE/.vbw/runtime" "$FAKE/.claude-plugin" "$FAKE/src" "$STUBS"
  cp "$REPO_ROOT/tools/test.sh" "$FAKE/tools/test.sh"
  cp -R "$PLUGIN_ROOT" "$FAKE/plugin"
  local b f t
  for b in bench-hooks bench-panel; do
    printf '#!/usr/bin/env bash\necho %s >> "$LOG"\n[ "${FAIL:-}" != %s ]\n' "$b" "$b" > "$FAKE/tools/$b.sh"
  done
  for f in a b timed-speed; do
    printf '#!/usr/bin/env bats\n@test "%s" { true; }\n' "$f" > "$FAKE/tests/$f.bats"
  done
  printf '1.0.0\n' > "$FAKE/VERSION"
  printf '{"name": "vbw", "version": "1.0.0"}\n' > "$FAKE/.claude-plugin/marketplace.json"
  printf '{"name": "vbw", "version": "1.0.0"}\n' > "$FAKE/marketplace.json"
  printf '# Changelog\n' > "$FAKE/CHANGELOG.md"
  printf '# Fake\n' > "$FAKE/README.md"
  printf 'code\n' > "$FAKE/src/app.txt"
  printf '.vbw/runtime/\n' > "$FAKE/.gitignore"
  printf '{"schema": 4, "protected": [], "checks": []}\n' > "$FAKE/.vbw/record.json"
  for t in shellcheck parallel node; do
    printf '#!/usr/bin/env bash\n{ printf %%s %s; printf " %%s" "$@"; echo; } >> "$LOG"\n' "$t" > "$STUBS/$t"
  done
  cat > "$STUBS/bats" << 'SH'
#!/usr/bin/env bash
{ printf %s bats; printf " %s" "$@"; echo; } >> "$LOG"
case " $* " in
  *" --jobs "*) [ "${FAIL:-}" != batch ] ;;
  *) [ "${FAIL:-}" != timed ] ;;
esac
SH
  printf '#!/usr/bin/env bash\necho 8\n' > "$STUBS/getconf"
  chmod +x "$STUBS"/*
  (
    cd "$FAKE" || exit 1
    git init -q
    git add -A
    git commit -q -m "chore(test): fake repo"
  )
  prove_with '{full: true, passed: true}'
}

# prove_with JQ_OBJECT: record a proof of the fake repository's current code,
# with the fields JQ_OBJECT gives (full, passed); the tree and head are the
# kernel's own (vbw_code_tree, vbw_head_tree), as vbw prove records them.
prove_with() {
  local tree head
  tree=$(cd "$FAKE" && vbw_kernel 'vbw_code_tree')
  head=$(cd "$FAKE" && vbw_kernel 'vbw_head_tree')
  jq -c --arg at "$AT" --arg tree "$tree" --arg head "$head" ". + {evidence: ({at: \$at, contract: \"c0ffee\", tree: \$tree, head: \$head, scope: [], checks: {},
      commands: {test: {status: \"pass\", exit: 0, seconds: 900, tail: \"ok\"}}, test_run: {status: \"pass\", exit: 0, seconds: 900, tail: \"ok\"}} + $1)}" \
    "$FAKE/.vbw/record.json" > "$TEST_ROOT/record.json"
  cp "$TEST_ROOT/record.json" "$FAKE/.vbw/record.json"
}

# bump: change only the four version files and the changelog.
bump() {
  printf '1.0.1\n' > "$FAKE/VERSION"
  jq '.version = "1.0.1"' "$FAKE/plugin/.claude-plugin/plugin.json" > "$TEST_ROOT/p.json" && cp "$TEST_ROOT/p.json" "$FAKE/plugin/.claude-plugin/plugin.json"
  printf '{"name": "vbw", "version": "1.0.1"}\n' > "$FAKE/.claude-plugin/marketplace.json"
  printf '{"name": "vbw", "version": "1.0.1"}\n' > "$FAKE/marketplace.json"
  printf '# Changelog\n\n## 1.0.1\n' > "$FAKE/CHANGELOG.md"
}

# fake_run ARGS...: run the copied script in the scratch repository; sets CODE
# and OUT (stdout and stderr).
fake_run() {
  : > "$LOG"
  CODE=0
  (cd "$FAKE" && PATH="$STUBS:$PATH" bash tools/test.sh "$@" < /dev/null) > "$TEST_ROOT/out" 2>&1 || CODE=$?
  OUT=$(cat "$TEST_ROOT/out")
}

bats_calls() { grep '^bats ' "$LOG" || true; }

# reused: only the benchmarks and the timed file ran, and the proof was named.
reused() {
  [ "$CODE" -eq 0 ] || { echo "exit $CODE: $OUT"; return 1; }
  grep -qx 'bench-hooks' "$LOG" && grep -qx 'bench-panel' "$LOG" || { echo "a benchmark did not run:"; cat "$LOG"; return 1; }
  [ "$(bats_calls | grep -c .)" -eq 1 ] && bats_calls | grep -q 'tests/timed-speed.bats' || { echo "not the timed file alone:"; cat "$LOG"; return 1; }
  ! bats_calls | grep -qE 'tests/(a|b)\.bats' || { echo "the suite ran again:"; cat "$LOG"; return 1; }
  ! grep -q '^shellcheck ' "$LOG" || { echo "the lint ran again:"; cat "$LOG"; return 1; }
  [[ "$OUT" == *"$AT"* ]] || { echo "the reused proof is not named: $OUT"; return 1; }
}

# everything: the whole release run ran: the lint, the benchmarks, the suite and the timed file.
everything() {
  grep -q '^shellcheck ' "$LOG" && grep -qx 'bench-hooks' "$LOG" || { echo "not the whole release run:"; cat "$LOG"; return 1; }
  bats_calls | grep -q 'tests/a.bats' && bats_calls | grep -q 'tests/timed-speed.bats' || { echo "not the whole suite:"; cat "$LOG"; return 1; }
}

@test "R164: with only the version files and the changelog changed since a passing full proof, the release run reuses it" {
  fake_repo
  bump
  fake_run --release
  reused
}

@test "R164: the same holds when the version change is committed" {
  fake_repo
  bump
  (cd "$FAKE" && git add -A && git commit -q -m "chore(release): 1.0.1")
  fake_run --release
  reused
}

@test "R164: any other changed file, committed or not, runs everything and says why" {
  fake_repo
  bump
  printf '# Fake, changed\n' > "$FAKE/README.md"
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
  [[ "$OUT" == *"README.md"* ]] || { echo "the reason does not name README.md: $OUT"; false; }
  (cd "$FAKE" && git add -A && git commit -q -m "docs: readme")
  fake_run --release
  everything
  [[ "$OUT" == *"README.md"* ]] || { echo "the reason does not name README.md: $OUT"; false; }
}

@test "R164: a new untracked file runs everything and says why" {
  fake_repo
  printf 'new\n' > "$FAKE/src/new.txt"
  fake_run --release
  everything
  [[ "$OUT" == *"src/new.txt"* ]] || { echo "the reason does not name src/new.txt: $OUT"; false; }
}

@test "R164: with no proof recorded, the release run runs everything and says why" {
  fake_repo
  jq 'del(.evidence)' "$FAKE/.vbw/record.json" > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" "$FAKE/.vbw/record.json"
  bump
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
  [[ "$OUT" == *"proof"* ]] || { echo "no reason given: $OUT"; false; }
}

@test "R164: when the last full proof failed, the release run runs everything and says why" {
  fake_repo
  prove_with '{full: true, passed: false, test_run: {status: "fail", exit: 1, seconds: 900, tail: "not ok"}, commands: {test: {status: "fail", exit: 1, seconds: 900, tail: "not ok"}}}'
  bump
  fake_run --release
  everything
  [[ "$OUT" == *"fail"* ]] || { echo "the reason does not say the proof failed: $OUT"; false; }
}

@test "R164: a partial proof never counts as a full one" {
  fake_repo
  prove_with '{full: false, passed: true}'
  bump
  fake_run --release
  everything
  [[ "$OUT" == *"proof"* ]] || { echo "no reason given: $OUT"; false; }
}

@test "R164: when the proof is reused, a failing benchmark or timed check still fails the run" {
  fake_repo
  bump
  FAIL=bench-hooks fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
  FAIL=bench-panel fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
  FAIL=timed fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
}

@test "R164: the CI shards run their whole share whatever proof is recorded" {
  fake_repo
  bump
  fake_run --shard 1/1
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
}
