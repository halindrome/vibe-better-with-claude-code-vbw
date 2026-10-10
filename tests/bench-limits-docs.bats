#!/usr/bin/env bats
# R151: the speed limits are the same everywhere and stated once in words. CI
# runs the hook benchmark with the same defaults as a local run (no CI-only
# hook or status line limit), and docs/guards.md, docs/statusline.md and the
# hot-path rule of CLAUDE.md state 20 ms per hook call, 60 ms for the status
# line and the busy-machine report; none still states 8 ms or 30 ms as the
# limit. L1: the files are read as text.

load helper

CI="$REPO_ROOT/.github/workflows/ci.yml"

# flat FILE: the file on one line, lower case, spaces squeezed.
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

# old_limits FILE: lines stating 8 ms or 30 ms as a limit or budget.
old_limits() {
  grep -inE '(^|[^0-9.])(8|30) ?ms' "$1" | grep -iE 'budget|limit|at most|within|≤|<=' || true
}

@test "R151: CI runs the benchmark with the local defaults: no CI-only hook or status line limit" {
  ! grep -nE 'VBW_HOOK_BUDGET|VBW_STATUSLINE_BUDGET' "$CI" || {
    echo "ci.yml still sets a limit of its own"
    false
  }
}

@test "R151: docs/guards.md states the 20 ms limit per hook call and the busy-machine report, and no longer 8 ms" {
  local f="$REPO_ROOT/docs/guards.md"
  flat "$f" | grep -qE '20 ?ms' || {
    echo "docs/guards.md does not state 20 ms"
    false
  }
  flat "$f" | grep -qE 'too busy|busy machine|machine is busy' || {
    echo "docs/guards.md does not describe the busy-machine report"
    false
  }
  [ -z "$(old_limits "$f")" ] || {
    echo "docs/guards.md still states an old limit:"
    old_limits "$f"
    false
  }
  ! flat "$f" | grep -qE '1x (that|the) startup|1x the platform' || {
    echo "docs/guards.md still states the relative limit"
    false
  }
}

@test "R151: docs/statusline.md states the 60 ms limit, and no longer 30 ms" {
  local f="$REPO_ROOT/docs/statusline.md"
  flat "$f" | grep -qE '60 ?ms' || {
    echo "docs/statusline.md does not state 60 ms"
    false
  }
  [ -z "$(old_limits "$f")" ] || {
    echo "docs/statusline.md still states an old limit:"
    old_limits "$f"
    false
  }
}

@test "R151: the hot-path rule of CLAUDE.md states 20 ms per hook call, 60 ms for the status line and the busy report" {
  local rule
  rule=$(grep -E '^- \*\*Hot paths:\*\*' "$REPO_ROOT/CLAUDE.md") || {
    echo "CLAUDE.md has no hot-path rule"
    false
  }
  printf '%s\n' "$rule" | grep -qE '20 ?ms' || {
    echo "the rule does not state 20 ms: $rule"
    false
  }
  printf '%s\n' "$rule" | grep -qE '60 ?ms' || {
    echo "the rule does not state 60 ms: $rule"
    false
  }
  printf '%s\n' "$rule" | grep -qi 'busy' || {
    echo "the rule does not state the busy-machine report: $rule"
    false
  }
  ! printf '%s\n' "$rule" | grep -qE '(^|[^0-9.])(8|30) ?ms|1x' || {
    echo "the rule still states an old limit: $rule"
    false
  }
}
