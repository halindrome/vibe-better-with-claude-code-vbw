#!/usr/bin/env bats
# R161: every subcommand of vbw req that the kernel accepts (plugin/lib/cmd-req.sh)
# is on VBW's whole surface: the top-level usage (vbw --help), the req help
# (vbw req --help) with a description that says what it records, the list of
# subcommands the help test exercises, and the panel's intent and result
# lines. A subcommand added to the kernel alone fails here. L1.

load helper

# accepted: the req subcommands cmd-req.sh dispatches (the arms of its case).
accepted() {
  awk '/case "\$sub" in/,/esac/' "$PLUGIN_ROOT/lib/cmd-req.sh" | grep -oE '^[[:space:]]+[a-z]+\)' | tr -d ' \t)'
}

@test "R161: cmd-req.sh accepts accept, reject and skip" {
  [ "$(accepted | LC_ALL=C sort | tr '\n' ' ')" = "accept reject skip " ] || { accepted; false; }
}

@test "R161: every req subcommand is in the top-level usage and in the req help" {
  local s top help
  top=$("$PLUGIN_ROOT/bin/vbw" --help 2>&1 || true)
  help=$("$PLUGIN_ROOT/bin/vbw" req --help 2>&1 || true)
  for s in $(accepted); do
    [[ "$top" == *"req $s "* ]] || { echo "vbw --help lacks req $s"; echo "$top" | grep ' req '; false; }
    [[ "$help" == *"req $s "* ]] || { echo "vbw req --help lacks req $s"; echo "$help"; false; }
  done
  [[ "$help" == *"Skip for now"* ]] || { echo "the req help does not say what skip records:"; echo "$help"; false; }
}

@test "R161: every req subcommand is exercised by the help test and named by the panel" {
  local s
  for s in $(accepted); do
    grep -qE "SUBCOMMANDS=.*(\||')req $s(\||')" "$REPO_ROOT/tests/help-every-command.bats" \
      || { echo "tests/help-every-command.bats does not exercise req $s"; false; }
    grep -q "'req $s':" "$PLUGIN_ROOT/hooks/panel-intent.js" || { echo "panel-intent.js has no line for req $s"; false; }
    grep -q "'req $s':" "$PLUGIN_ROOT/hooks/panel-lines.js" || { echo "panel-lines.js has no line for req $s"; false; }
  done
}
