#!/usr/bin/env bats
# R142 (L1): CI runs the suite on macOS /bin/bash 3.2 and on both Linux bash 5
# systems as parallel shard jobs of the one Tests job (2.0.38: an unsplit Linux
# job set the run's length, about an hour), and the manifest validation job is
# unchanged. The matrix base lists the three systems with shard: [1, ..., N];
# each include entry names one of them, so it joins every shard. The
# workflow file is read as text: no YAML parser is a VBW dependency. The real
# proof is a CI run on GitHub after the owner pushes (L4); this file proves only
# what the file says.

load helper

CI="$REPO_ROOT/.github/workflows/ci.yml"

# job NAME: the lines of one job of ci.yml, from "  NAME:" to the next job.
job() {
  awk -v j="  $1:" '
    $0 == j { on = 1; print; next }
    on && /^  [A-Za-z_-]+:/ { exit }
    on { print }
  ' "$CI"
}

# shard_list: the numbers of the Tests matrix's shard list, one per line.
shard_list() {
  job test | sed -n 's/^ *shard: *\[\(.*\)\] *$/\1/p' | tr ',' '\n' | tr -d ' '
}

@test "R142: the Tests matrix splits every system into 3 to 5 shards numbered 1 to N" {
  local list n
  list=$(shard_list)
  [ -n "$list" ] || {
    echo "no shard: [...] list in the Tests matrix"
    false
  }
  n=$(printf '%s\n' "$list" | grep -c .)
  [ "$n" -ge 3 ] && [ "$n" -le 5 ] || {
    echo "$n shards"
    false
  }
  [ "$(printf '%s\n' "$list" | tr '\n' ' ')" = "$(seq 1 "$n" | tr '\n' ' ')" ] || {
    echo "shards: $list"
    false
  }
  job test | grep -qE '^ +os: *\[ *macos-latest, *ubuntu-latest, *ubuntu-26\.04 *\] *$' || {
    echo "the matrix base is not os: [macos-latest, ubuntu-latest, ubuntu-26.04]"
    false
  }
}

@test "R142: each system's entry joins the shards: one include entry per os of the base" {
  local entries
  entries=$(job test | awk '
    /^ *- name:/ { if (n) print n "|" o; n = $0; sub(/^ *- name: */, "", n); o = ""; next }
    n && /^ *os:/ { o = $0; sub(/^ *os: */, "", o) }
    /^    steps:/ { if (n) print n "|" o; n = "" }
  ')
  [ "$(printf '%s\n' "$entries" | grep -c '|macos-latest$')" -eq 1 ] || {
    echo "$entries"
    false
  }
  [ "$(printf '%s\n' "$entries" | grep -c '|ubuntu-latest$')" -eq 1 ] && [ "$(printf '%s\n' "$entries" | grep -c '|ubuntu-26.04$')" -eq 1 ] || {
    echo "$entries"
    false
  }
  ! job test | grep -qE '^ +exclude:' || {
    echo "an exclude list changes which entries run"
    false
  }
}

@test "R142: every job runs tools/test.sh --shard K/N with N the shard count, and no job runs the release run unsplit" {
  local n step
  n=$(shard_list | grep -c .)
  step=$(job test)
  printf '%s\n' "$step" | grep -qE "SHARD: *\\\$\\{\\{ *matrix\\.shard *\\}\\}" || {
    echo "the shard number does not reach the run step as SHARD"
    false
  }
  printf '%s\n' "$step" | grep -qE "SHARDS: *\"?$n\"?$" || {
    echo "SHARDS is not the shard count $n"
    false
  }
  printf '%s\n' "$step" | grep -qF 'bash tools/test.sh --shard "$SHARD/$SHARDS"' || {
    echo "no shard run"
    false
  }
  ! printf '%s\n' "$step" | grep -qF 'bash tools/test.sh --release' || {
    echo "a job still runs the release run unsplit"
    false
  }
}

@test "R142: every shard checks out into a path with a space and puts the target bash first on PATH" {
  local step
  step=$(job test)
  printf '%s\n' "$step" | grep -q 'path: src dir'
  printf '%s\n' "$step" | grep -q 'working-directory: src dir'
  printf '%s\n' "$step" | grep -qF 'export PATH="${{ matrix.bash_path }}:$PATH"'
  # One step list for the whole matrix: no step is limited to some entries.
  ! printf '%s\n' "$step" | grep -qE 'if: .*matrix\.(os|name|bash_path)' || {
    echo "a step is limited to some entries"
    false
  }
}

@test "R142: the CI panel budget is unchanged and CI sets no hook or status line limit of its own" {
  local step
  step=$(job test)
  printf '%s\n' "$step" | grep -q 'VBW_PANEL_BUDGET_MS: "3"'
  # R151: the hook and status line limits are the local defaults.
  ! printf '%s\n' "$step" | grep -qE 'VBW_HOOK_BUDGET|VBW_STATUSLINE_BUDGET'
}

@test "R142: shards never cancel each other and a failing shard fails CI" {
  job test | grep -qE '^      fail-fast: false$'
  ! grep -q 'continue-on-error' "$CI" || {
    echo "continue-on-error hides a failing shard"
    false
  }
  ! job test | grep -E 'tools/test\.sh' | grep -qE '\|\| *(true|:)|; *true' || {
    echo "the suite's exit code is swallowed"
    false
  }
}

@test "R142: the job name tells the shards apart" {
  job test | grep -qE '^    name: .*matrix\.name.*matrix\.shard' || {
    echo "shard jobs would share one name"
    false
  }
}

@test "R142: the plugin manifest validation job is unchanged" {
  [ "$(job validate)" = '  validate:
    name: Plugin manifest validation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: 22
      - name: Validate plugin and marketplaces
        run: |
          npm install -g @anthropic-ai/claude-code
          claude plugin validate ./plugin
          claude plugin validate .
          node --check plugin/workflows/*.js 2>/dev/null || [ -z "$(ls plugin/workflows/*.js 2>/dev/null)" ]' ] || {
    job validate
    false
  }
}
