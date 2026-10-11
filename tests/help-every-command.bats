#!/usr/bin/env bats
# R163 (docs/workflows.md): --help or -h after any command the kernel dispatches
# (the list in plugin/bin/vbw, walked here, so a new command without help fails)
# prints that command's usage, starting "usage: vbw CMD", on standard output and
# exits 0. The same holds right after a subcommand (vbw run start --help). It
# changes nothing: every file under .vbw is byte-identical, git HEAD and the
# index are unchanged. It works outside a VBW project, while a run is open, and
# from a session that does not own the open run. A text argument that merely
# contains --help is still text. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'true\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"]}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: []}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}]}' | "$VBW" apply > /dev/null
  git add -A
  git commit -q -m "chore(test): planned"
}

teardown() { vbw_teardown; }

# commands: every command name in the kernel's dispatch list.
commands() {
  grep -E '^[[:space:]]+init\|' "$PLUGIN_ROOT/bin/vbw" | head -n 1 | sed -E 's/^[[:space:]]+//; s/\).*$//' | tr '|' '\n'
}

# Subcommands whose help must not do their work.
SUBCOMMANDS='run start|run end|run confirm|todo add|todo sort|todo done|todo drop|spec sync|spec add|plan done|plan reset|fix done|fix retry|fix check|req accept|req reject|req skip|qa finding|qa record|milestone start|milestone rename|config set|auto on|auto off|tier raise|legacy remove|legacy choose|interview set|interview keep|suggest decline'

# state: the bytes of every file under .vbw, git HEAD and the index.
state() {
  {
    [ ! -d .vbw ] || find .vbw -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done
    git rev-parse HEAD 2> /dev/null || true
    git ls-files --stage 2> /dev/null || true
  } | cksum
}

# helps ARGS...: vbw ARGS prints its command's usage on stdout, exits 0, and
# changes nothing. The usage starts "usage: vbw" and the first word of ARGS.
helps() {
  local before out err code=0
  before=$(state)
  out=$("$VBW" "$@" < /dev/null 2> "$TEST_ROOT/err") || code=$?
  err=$(cat "$TEST_ROOT/err")
  [ "$code" -eq 0 ] || { printf 'vbw %s: exit %s\nstdout: %s\nstderr: %s\n' "$*" "$code" "$out" "$err"; return 1; }
  case "$(printf '%s\n' "$out" | head -n 1)" in
    "usage: vbw $1" | "usage: vbw $1 "*) ;;
    *) printf 'vbw %s: stdout does not start with "usage: vbw %s":\n%s\n' "$*" "$1" "$out"; return 1 ;;
  esac
  [ "$(state)" = "$before" ] || { printf 'vbw %s changed .vbw, HEAD or the index\n' "$*"; return 1; }
}

@test "R163: the dispatch list is found" {
  [ "$(commands | wc -l | tr -d ' ')" -ge 30 ] || { commands; false; }
  commands | grep -qx apply
}

@test "R163: vbw CMD --help and vbw CMD -h print the command's usage and change nothing, for every dispatched command" {
  local c
  for c in $(commands); do
    helps "$c" --help || return 1
    helps "$c" -h || return 1
  done
}

@test "R163: the flag right after a subcommand prints the command's usage and does not do the subcommand's work" {
  local pair a b
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  while IFS= read -r pair; do
    a=${pair%% *}
    b=${pair#* }
    VBW_SESSION_ID=s1 helps "$a" "$b" --help || return 1
    VBW_SESSION_ID=s1 helps "$a" "$b" -h || return 1
  done < <(printf '%s\n' "$SUBCOMMANDS" | tr '|' '\n')
  jq -e '.lease.kind == "plan"' .vbw/record.json
}

@test "R163: help works while a run is open and from a session that does not own it" {
  local c
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  for c in $(commands); do
    VBW_SESSION_ID=s2 helps "$c" --help || return 1
  done
  VBW_SESSION_ID=s2 helps run end --help
  VBW_SESSION_ID=s2 helps apply -h
  jq -e '.lease.kind == "plan" and .lease.session == "s1"' .vbw/record.json
}

@test "R163: help works outside a VBW project, in a git repository and in a plain folder, and creates nothing" {
  local d c
  for d in "$TEST_ROOT/plain git" "$TEST_ROOT/plain folder"; do
    mkdir -p "$d"
    cd "$d"
    [ "$d" != "$TEST_ROOT/plain git" ] || vbw_git_project
    for c in $(commands); do
      helps "$c" --help || return 1
    done
    [ ! -e .vbw ] || { echo "help created .vbw in $d"; false; }
  done
}

@test "R163: a text argument that only contains --help is still taken as text" {
  run "$VBW" todo add "explain --help" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '[.todos[].text] | index("explain --help") != null' .vbw/record.json
}
