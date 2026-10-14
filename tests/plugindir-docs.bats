#!/usr/bin/env bats
# R185: the local development path is written down. CONTRIBUTING.md's Local
# development section says to start with claude --plugin-dir ./plugin, that
# the vbw on PATH and the status line's version are then the working tree's,
# how to check it (vbw --version, vbw doctor, the status line), and what
# happens when a VBW release is also installed. docs/statusline.md says which
# copy's version the status line shows, and the old claim that it always runs
# the newest installed copy is qualified. docs/diagnostics.md says vbw doctor
# checks the vbw on PATH against the loaded plugin. L1.

load helper

CONTRIB="$REPO_ROOT/CONTRIBUTING.md"
SL="$REPO_ROOT/docs/statusline.md"
DIAG="$REPO_ROOT/docs/diagnostics.md"

# local_dev: CONTRIBUTING.md's Local development section.
local_dev() { sed -n '/^## Local development/,/^## /p' "$CONTRIB"; }

@test "R185: CONTRIBUTING.md's Local development section starts VBW from the working tree and says its kernel is then the one on PATH" {
  local s
  s=$(local_dev)
  [ -n "$s" ]
  printf '%s\n' "$s" | grep -qF 'claude --plugin-dir ./plugin'
  printf '%s\n' "$s" | grep -qiE 'vbw[^.]*on (the )?PATH|PATH[^.]*vbw' || {
    echo "the section does not say which vbw is on PATH"
    false
  }
  printf '%s\n' "$s" | grep -qi 'working tree'
}

@test "R185: it says how to check: vbw --version, vbw doctor and the status line's version" {
  local s
  s=$(local_dev)
  printf '%s\n' "$s" | grep -qF 'vbw --version'
  printf '%s\n' "$s" | grep -qF 'vbw doctor'
  printf '%s\n' "$s" | grep -qi 'status line'
}

@test "R185: it says what happens when a VBW release is also installed" {
  local s
  s=$(local_dev)
  printf '%s\n' "$s" | grep -qiE 'installed|release' || {
    echo "the section does not mention an installed release"
    false
  }
  printf '%s\n' "$s" | grep -qiE 'marketplace|installed (release|copy|VBW)|VBW release'
}

@test "R185: docs/statusline.md says the status line of a --plugin-dir session shows the working tree's version, and other sessions the installed one" {
  grep -qF -- '--plugin-dir' "$SL" || {
    echo "docs/statusline.md does not mention --plugin-dir"
    false
  }
  # From the first mention to the next heading: the version shown, and the installed copy otherwise.
  sed -n '/--plugin-dir/,/^## /p' "$SL" | grep -qi 'version'
  sed -n '/--plugin-dir/,/^## /p' "$SL" | grep -qi 'installed'
}

@test "R185: docs/diagnostics.md says vbw doctor compares the vbw on PATH with the loaded plugin" {
  sed -n '/^### vbw doctor/,/^##/p' "$DIAG" | grep -qF 'PATH' || {
    echo "the vbw doctor section does not mention PATH"
    false
  }
  sed -n '/^### vbw doctor/,/^##/p' "$DIAG" | grep -qi 'loaded'
}
