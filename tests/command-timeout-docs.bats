#!/usr/bin/env bats
# R153: docs/proof.md states the project commands' time limit: 3600 seconds
# (60 minutes) by default, a project's own limit set with vbw config set
# command_timeout SECONDS, its range (1 to 86400) and what a stop by the limit
# looks like (the command recorded as timeout, the report naming the limit and
# how to raise it), and no longer the old 900 seconds (15 minutes). L1: the
# file is read as text.

load helper

DOC="$REPO_ROOT/docs/proof.md"

# flat: the guide on one line, lower case, spaces squeezed.
flat() { tr '\n' ' ' < "$DOC" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

has() { flat | grep -qE -- "$1" || {
  echo "docs/proof.md lacks: $1"
  return 1
}; }

@test "R153: docs/proof.md states the default limit of the test command, 60 minutes" {
  has '3600 seconds|60 minutes'
  ! flat | grep -qE '(^|[^0-9])900 seconds|15 minutes' || {
    echo "docs/proof.md still states the old 15-minute limit"
    false
  }
}

@test "R153: docs/proof.md says how a project sets its own limit and the allowed range" {
  has 'vbw config set command_timeout'
  has '1 to 86400'
  has 'command_timeout default'
}

@test "R153: docs/proof.md says what a stop by the limit looks like and how to raise the limit" {
  has 'timeout'
  has 'stopped[^.]*time limit|time limit[^.]*stop'
  has 'raise'
}
