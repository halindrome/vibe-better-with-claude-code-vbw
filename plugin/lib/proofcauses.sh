#!/usr/bin/env bash
# Why a proof runs everything (docs/proof.md, R168). When VBW cannot tell what
# a change affects, every check and test file runs and each cause is named in
# plain words. A cause is one line of text; no cause means the reuse rule of
# proofreuse.sh decides alone, unit by unit. A change to the project's files is
# never a cause: a content change to a file no recorded run read affects
# nothing that was run; an added or deleted file re-runs the units that listed
# its folder or read it, through their own read lists; a changed approved
# command, single-file form or list of test files re-runs only what runs
# through it, through the units' fingerprints. A proof cut short is no cause
# either: it saved nothing, or runs as complete as any proof's, so the next
# proof reuses as if it had not run.

# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"
# shellcheck source=reads.sh
. "$VBW_LIB/reads.sh"

# proofcauses_find RECORD FULL HEAD [KIND]: every cause for this proof, one per
# line, in a fixed order; nothing when the reuse rule may decide alone. FULL is
# 1 for vbw prove --full. HEAD is the tree of the committed code. KIND is
# "prove" (the default) or "fix": a second vbw prove with nothing committed
# since a passing proof is a deliberate re-run and a cause; vbw fix done after
# that proof is not, a passing proof of the same code is exactly what it needs.
proofcauses_find() {
  local probe
  [ "$2" != 1 ] || printf 'vbw prove --full\n'
  proofreuse_store_read | jq -e '(.runs | length) > 0' > /dev/null || printf 'this clone has no earlier recorded run\n'
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || true
  probe=$(reads_probe "$VBW_RUNTIME" 2>&1) || printf '%s\n' "$probe"
  if [ "${4:-prove}" != fix ] && proofreuse_proved "$1" "$3"; then
    printf 'nothing was committed since the last passing proof\n'
  fi
}
