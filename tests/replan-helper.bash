# shellcheck shell=bash
# Shared fixtures for planning again (M21: R156 to R159). Load after helper:
#   load helper
#   load replan-helper
#
# replan_project builds a milestone M1 with R1, R2 and R3 [auto] and applies
# REPLAN_DOC: P1 (R1: plans P1.1 then P1.2) and P2 (R2: plan P2.1), both
# standard, with no checks and no rules. R3 has no phase yet.

# replan_edit JQ_EXPR: a hand edit of the record, as a test needs a state no
# command gives quickly. It keeps the protected list in step and drops the
# status line's side file (.vbw/runtime/glance.json), as a kernel write would.
replan_edit() {
  jq "$1 | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) else . end" .vbw/record.json > "$TEST_ROOT/replan-edit.json" \
    && cp "$TEST_ROOT/replan-edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

REPLAN_DOC='{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "goal": "Customers pay", "criteria": ["a payment is saved"], "tier": "standard"},
                 {"id": "P2", "title": "Receipt", "reqs": ["R2"], "goal": "Customers get a receipt", "criteria": ["a receipt is shown"], "tier": "standard"}],
  "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay form", "reqs": ["R1"], "files": ["src/a.txt"], "after": [], "tasks": ["form"]},
            {"id": "P1.2", "phase": "P1", "title": "Pay button", "reqs": ["R1"], "files": ["src/b.txt"], "after": ["P1.1"], "tasks": ["button"]},
            {"id": "P2.1", "phase": "P2", "title": "Receipt page", "reqs": ["R2"], "files": ["src/c.txt"], "after": [], "tasks": ["page"]}],
  "checks": []}'

replan_project() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [auto] A customer can refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf '%s' "$REPLAN_DOC" | "$VBW" apply > /dev/null
}

# replan_start PLAN: the plan has started (it is done).
replan_start() { replan_edit "(.plans[] | select(.id == \"$1\")).status = \"done\""; }

# replan_apply MODE DOC: vbw apply (MODE full), vbw apply --add or vbw apply --patch
# with DOC on stdin; sets status and output (stdout and stderr) like bats' run.
replan_apply() {
  local flag=()
  case "$1" in add) flag=(--add) ;; patch) flag=(--patch) ;; esac
  status=0
  output=$(printf '%s' "$2" | "$VBW" apply ${flag[@]+"${flag[@]}"} 2>&1) || status=$?
}

# replan_refused MODE DOC: the apply is refused (non-zero exit) and the record's
# bytes stay as they were; the message is left in output.
replan_refused() {
  local before
  before=$(cksum < .vbw/record.json)
  replan_apply "$1" "$2"
  [ "$status" -ne 0 ] || { echo "vbw apply ($1) was accepted: $output"; return 1; }
  [ "$(cksum < .vbw/record.json)" = "$before" ] || { echo "vbw apply ($1) changed the record: $output"; return 1; }
}

# replan_accepted MODE DOC: the apply succeeds.
replan_accepted() {
  replan_apply "$1" "$2"
  [ "$status" -eq 0 ] || { echo "vbw apply ($1) was refused: $output"; return 1; }
}

# replan_part EXPR: a part of the record in canonical form.
replan_part() { jq -cS "$1" .vbw/record.json; }

# replan_doc JQ_EXPR: REPLAN_DOC changed by JQ_EXPR, compact.
replan_doc() { printf '%s' "$REPLAN_DOC" | jq -c "$1"; }
