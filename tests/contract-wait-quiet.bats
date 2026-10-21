#!/usr/bin/env bats
# R160 (docs/proof.md): while a check a fix added waits for the user's
# approval, every vbw command stays quiet on its error output: the kernel never
# captures NUL-separated output in a shell variable (bash 5 prints "ignored
# null byte in input" for each, bash 3.2 drops the bytes without a word, so
# the wait list would be wrong there). The first test is the rule over the
# kernel's code, so it fails on every shell; the second is the behaviour,
# which only bash 4.4 and later can show. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# nul_captures FILE: every $( ... ) in FILE whose command runs jq -j with a
# "\u0000" separator and does not pipe the bytes on through tr: the capture
# would hold NUL bytes.
nul_captures() {
  awk '{ buf = buf $0 "\n" }
    END {
      n = length(buf); i = 1
      while (i <= n) {
        if (substr(buf, i, 2) == "$(") {
          depth = 1; j = i + 2
          while (j <= n && depth > 0) {
            c = substr(buf, j, 1)
            if (c == "(") depth++; else if (c == ")") depth--
            j++
          }
          cap = substr(buf, i, j - i)
          if (cap ~ /jq -j/ && cap ~ /\\u0000/ && cap !~ /\| *tr /) print FILENAME ": " substr(cap, 1, 90)
          i = j
        } else i++
      }
    }' "$1"
}

@test "R160: no kernel script captures NUL-separated jq output in a shell variable" {
  local f bad=""
  for f in "$PLUGIN_ROOT"/lib/*.sh "$PLUGIN_ROOT"/bin/vbw; do
    bad="$bad$(nul_captures "$f")"
  done
  [ -z "$bad" ] || { printf 'captures that would hold NUL bytes (use one path per line, or read -d ""):\n%s\n' "$bad"; false; }
}

@test "R160: the rule catches the capture it is for" {
  printf 'held=$(printf %%s "$1" | jq -j %s.files[]? | . + "\\u0000"%s 2> /dev/null) || x=1\nok=$(git ls-files -z | tr -cd "\\000" | wc -c)\n' "'" "'" > "$TEST_ROOT/bad.sh"
  run nul_captures "$TEST_ROOT/bad.sh"
  [ "$(printf '%s\n' "$output" | grep -c .)" = 1 ] || { echo "$output"; false; }
  [[ "$output" == *'jq -j'* && "$output" != *"ls-files"* ]] || { echo "$output"; false; }
}

@test "R160: vbw next says nothing on its error output while a check a fix added waits for approval" {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "Customers pay", criteria: ["paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
  "$VBW" qa finding R1 "a payment of zero is accepted" > /dev/null
  local f
  f=$(jq -r '[.fixes[] | select(.source == "qa")][-1].id' .vbw/record.json)
  printf 'grep -qx paid src/pay.txt\n' > tests/r1-regression.sh
  printf '%s' '{"run": ["sh", "tests/r1-regression.sh"], "files": ["tests/r1-regression.sh"]}' | "$VBW" fix check "$f" > /dev/null
  run bash -c '"$1" next --json 2>&1 1> /dev/null' _ "$VBW"
  [ -z "$output" ] || { echo "$output"; false; }
  run "$VBW" status
  [ "$status" -eq 0 ]
}
