#!/usr/bin/env bash
# The release-run fixture shared by tests/release-reuse.bats (R164) and
# tests/release-reuse-partial.bats (R170): a scratch git repository with a copy
# of tools/test.sh and of the plugin, whose bats, shellcheck, parallel, node,
# getconf and benchmarks are stand-ins that log their calls to $LOG.

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

