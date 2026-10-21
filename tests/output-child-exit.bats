#!/usr/bin/env bats
# A kernel write that waits for a slow reader survives a child of the writer
# exiting meanwhile. macOS /bin/bash 3.2 catches SIGCHLD without SA_RESTART
# (bash 4.2 added it), so there a builtin printf or echo blocked on a full pipe
# (Claude Code's Bash tool, a terminal, bats) fails with EINTR, "write error:
# Interrupted system call", when a child exits, and its text is lost; under
# set -e the command fails (CI, tests/machine-turns.bats, vbw check). A loop fed
# by a process substitution has its producer as a live child the whole time it
# runs. The rule, tools/check-loop-writes.sh: no builtin write in such a loop's
# own shell; vbw_out (core.sh) writes from a child of its own, or the producer
# is piped into the loop. Each run below fills the pipe first, so the write
# waits, and lets a child of the writer exit while it does. L1.

load helper
load fixture-helper

# shop: a project with two approved checks; each marks that it ran.
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'touch "$TEST_ROOT/ran.$1"\n' > tests/ok.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/ok.sh","C1"], files:["tests/ok.sh"]},
                 {id:"C2", req:"R1", run:["sh","tests/ok.sh","C2"], files:["tests/ok.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build shop shop; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# wait_for PATH: wait (up to 30 s) until PATH exists.
wait_for() {
  local i
  for ((i = 0; i < 600; i++)); do
    [ ! -e "$1" ] || return 0
    sleep 0.05
  done
  return 1
}

# full_pipe READY CMD...: CMD with its output into a pipe a filler fills first,
# so CMD's writes wait for the reader, which starts once the function READY has
# returned. The output (the filler's NULs removed) goes to $TEST_ROOT/out,
# CMD's exit code to $TEST_ROOT/code and READY's to $TEST_ROOT/ready.
full_pipe() {
  local ready=$1
  shift
  (
    head -c 300000 /dev/zero &
    code=0
    "$@" < /dev/null 2>&1 || code=$?
    printf '%s\n' "$code" > "$TEST_ROOT/code"
    wait
  ) | {
    r=0
    "$ready" || r=$?
    printf '%s\n' "$r" > "$TEST_ROOT/ready"
    tr -d '\000' > "$TEST_ROOT/out"
  }
}

# producer_gone: the writer marked its write; let the producer exit and wait until it has.
producer_gone() {
  local r=0
  wait_for "$TEST_ROOT/writing" || r=1
  : > "$TEST_ROOT/go"
  wait_for "$TEST_ROOT/gone" || r=1
  return "$r"
}

# checks_done: both checks ran and vbw check removed its run folder: it is printing.
checks_done() {
  local i
  wait_for "$TEST_ROOT/ran.C2" || return 1
  for ((i = 0; i < 600; i++)); do
    set -- .vbw/runtime/run.*
    [ -e "$1" ] || return 0
    sleep 0.05
  done
  return 1
}

@test "vbw_out writes all of its text while the producer of the loop it writes in exits" {
  # The producer gives one line, then exits only once the reader says so, while vbw_out waits.
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  full_pipe producer_gone vbw_kernel 'while IFS= read -r l; do
      : > "$TEST_ROOT/writing"
      vbw_out "%s\n" "line $l, whole"
    done < <(printf "1\n"; until [ -e "$TEST_ROOT/go" ]; do sleep 0.05; done; : > "$TEST_ROOT/gone")'
  cat "$TEST_ROOT/out"
  [ "$(cat "$TEST_ROOT/ready")" = 0 ]
  [ "$(cat "$TEST_ROOT/code")" = 0 ]
  grep -qx 'line 1, whole' "$TEST_ROOT/out"
  ! grep -q 'Interrupted system call' "$TEST_ROOT/out"
}

@test "vbw check prints every result and passes when its output waits for a slow reader" {
  full_pipe checks_done "$VBW" check C1 C2
  cat "$TEST_ROOT/out"
  [ "$(cat "$TEST_ROOT/ready")" = 0 ]
  [ "$(cat "$TEST_ROOT/code")" = 0 ]
  grep -q '^C1 pass' "$TEST_ROOT/out"
  grep -q '^C2 pass' "$TEST_ROOT/out"
  ! grep -q 'Interrupted system call' "$TEST_ROOT/out"
}

@test "vbw_die says why and exits with its code even when a child exits while the message waits for the reader" {
  # Under set -e, as the kernel runs: a failed write would end the shell with 1, before the exit code it names.
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  full_pipe producer_gone vbw_kernel 'set -e
    while IFS= read -r l; do
      : > "$TEST_ROOT/writing"
      vbw_die "stopped at line $l" 3
    done < <(printf "1\n"; until [ -e "$TEST_ROOT/go" ]; do sleep 0.05; done; : > "$TEST_ROOT/gone")'
  cat "$TEST_ROOT/out"
  [ "$(cat "$TEST_ROOT/ready")" = 0 ]
  [ "$(cat "$TEST_ROOT/code")" = 3 ]
  grep -qx 'vbw: stopped at line 1' "$TEST_ROOT/out"
  ! grep -q 'Interrupted system call' "$TEST_ROOT/out"
}

# The rule.

rule() { bash "$REPO_ROOT/tools/check-loop-writes.sh" "$@"; }

# planted TEXT: a directory holding one shell file with TEXT from its line 4
# (after a header comment); prints the directory.
planted() {
  local d
  d=$(mktemp -d "$TEST_ROOT/plant.XXXXXX")
  printf '#!/usr/bin/env bash\n# A planted file.\n\n%s\n' "$1" > "$d/cmd-plant.sh"
  printf '%s\n' "$d"
}

@test "no shipped shell code writes with a builtin in the shell of a loop fed by a process substitution" {
  run rule "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "self-test: the rule catches each builtin write in a loop fed by a process substitution, naming its line" {
  local case line
  # Each case: the line the write is on, a colon, the planted code.
  for case in \
    "5:while IFS= read -r l; do
  printf '%s\n' \"\$l\"
done < <(jq -r '.[]' \"\$f\")" \
    "4:while IFS= read -r l; do echo \"\$l\"; done < <(printf 'a\n')" \
    "5:while IFS= read -r l; do
  printf 'vbw: %s -> %s\n' \"\$l\" \"\$x\" >&2
done < <(git log --format=%H)" \
    "4:while IFS= read -r -d '' a; do printf '%s\n' \"\$a\"; done \\
  < <(find . -print0)" \
    "6:  while IFS= read -r l; do
    for r in \$l; do
      [ \"\$r\" = x ] && { printf '  %s\n' \"\$r\"; break; }
    done
  done < <(git log --format=%s)" \
    "5:while IFS= read -r l; do
  printf '%s\n' \"\$l\" 2> /dev/null
done < <(jq -r '.[]' \"\$f\")" \
    "5:while IFS= read -r l; do
  if [ -f \"\$l\" ]; then printf 'x\n'; fi
done < <(jq -r '.[]' \"\$f\")" \
    "6:while IFS= read -r l; do
  out=\$(jq -r . \"\$l\")
  printf '%s\n' \"\${out}\"
done < <(jq -r '.[]' \"\$f\")"; do
    line=${case%%:*}
    run rule "$(planted "${case#*:}")"
    [ "$status" -ne 0 ] || { echo "not caught: ${case#*:}"; false; }
    [[ "$output" == *"cmd-plant.sh:$line:"* ]] || { echo "not named at line $line: ${case#*:}"; echo "$output"; false; }
  done
}

@test "self-test: the rule passes writes in a child of their own or into a file, and loops fed by a pipe" {
  local code
  for code in \
    "while IFS= read -r l; do
  vbw_out '%s\n' \"\$l\"
  vbw_out 'vbw: %s -> %s\n' \"\$l\" \"\$x\" >&2
done < <(jq -r '.[]' \"\$f\")" \
    "while IFS= read -r l; do
  printf '%s\n' \"\$l\" > \"\$dir/one\"
  printf '%s\n' \"\$l\" >> \"\$dir/all\"
  printf '%s\n' \"\$l\" &> \"\$dir/both\"
  [ -z \"\$l\" ] || printf '%s\0' \${a[@]+\"\${a[@]}\"} > \"\$dir/u/\$n\"
done < <(jq -r '.[]' \"\$f\")" \
    "while IFS= read -r l; do
  x=\$(printf '%s' \"\$l\" | jq .)
  t=\$(cd \"\$l\" 2> /dev/null && printf '%s/%s' \"\$(pwd -P)\" x)
  printf '%s' \"\$l\" | jq -e . > /dev/null
  ( printf 'in a subshell\n' )
done < <(jq -r '.[]' \"\$f\")" \
    "jq -r '.[]' \"\$f\" | while IFS= read -r l; do printf '%s\n' \"\$l\"; done" \
    "while IFS= read -r -d '' plan; do
  awk '{ print }' \"\$plan\" | while IFS= read -r p; do
    printf 'N\t%s\n' \"\$p\"
  done
done < <(find . -print0)" \
    "while IFS= read -r l; do
  command -v printf > /dev/null
  vbw_die \"use printf; echo it\"
  cat << 'EOF'
printf 'a heredoc line, not code'
EOF
done < <(jq -r '.[]' \"\$f\")"; do
    run rule "$(planted "$code")"
    [ "$status" -eq 0 ] || { echo "refused: $code"; echo "$output"; false; }
  done
}
