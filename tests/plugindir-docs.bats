#!/usr/bin/env bats
# R185: the local development path is written down with its commands.
# CONTRIBUTING.md names claude --plugin-dir ./plugin and the checks vbw
# --version and vbw doctor; docs/statusline.md names --plugin-dir;
# docs/diagnostics.md's vbw doctor section names PATH. L1.

load helper

CONTRIB="$REPO_ROOT/CONTRIBUTING.md"
SL="$REPO_ROOT/docs/statusline.md"
DIAG="$REPO_ROOT/docs/diagnostics.md"

@test "R185: CONTRIBUTING.md names the start command and the checks: claude --plugin-dir ./plugin, vbw --version, vbw doctor" {
  grep -qF 'claude --plugin-dir ./plugin' "$CONTRIB"
  grep -qF 'vbw --version' "$CONTRIB"
  grep -qF 'vbw doctor' "$CONTRIB"
}

@test "R185: docs/statusline.md names --plugin-dir" {
  grep -qF -- '--plugin-dir' "$SL"
}

@test "R185: docs/diagnostics.md's vbw doctor section names PATH" {
  sed -n '/^### vbw doctor/,/^##/p' "$DIAG" | grep -qF 'PATH' || {
    echo "the vbw doctor section does not mention PATH"
    false
  }
}
