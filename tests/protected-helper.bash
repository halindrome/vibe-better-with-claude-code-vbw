# shellcheck shell=bash
# Projects with many checks (R150). Load after helper:
#   load helper
#   load protected-helper
#
# A record with more than 50 checks carries the protected field: every file an
# approved check protects (the union of all checks' files, each path once, in
# sorted order), right after lease, and is schema 4. One with 50 checks or fewer
# has no such field and keeps schema 1, 2 or 3 (R46).

# protected_base: in the current folder, a git project with VBW and the
# requirements R1 and R2.
protected_base() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
}

# protected_doc N: the vbw apply document for phase P1, plan P1.1 (writing
# src/pay.txt) and N checks C1..CN of R1 and R2. Check K runs tests/cK.sh and
# lists tests/shared.sh then tests/cK.sh (the shared file is listed by every
# check, and the lists are not in sorted order); the last check lists no files.
# The check scripts are written too.
protected_doc() {
  local i
  for ((i = 1; i <= $1; i++)); do printf 'grep -qx paid src/pay.txt\n' > "tests/c$i.sh"; done
  printf 'true\n' > tests/shared.sh
  jq -nc --argjson n "$1" '{
    phases: [{id: "P1", title: "Pay", reqs: ["R1", "R2"], goal: "Customers pay and get refunds", criteria: ["src/pay.txt says paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1", "R2"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay", "refund", "note"]}],
    checks: [range(1; $n + 1) | {id: "C\(.)", req: (if . % 2 == 0 then "R2" else "R1" end), run: ["sh", "tests/c\(.).sh"]}
             + (if . == $n then {} else {files: ["tests/shared.sh", "tests/c\(.).sh"]} end)],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}, {req: "R2", text: "a refund is paid back", check: "C2"}]}'
}

# protected_apply N [JQ_FILTER]: apply protected_doc N (through FILTER when given).
protected_apply() {
  protected_doc "$1" | jq -c "${2:-.}" | "$VBW" apply > /dev/null
}

# protected_union [FILE]: the union of the record's check files, sorted, each once.
protected_union() {
  jq -c '[.checks[].files // [] | .[]] | unique' "${1:-.vbw/record.json}"
}

# record_edit FILTER [FILE]: change the record by hand, as a restored or older
# project would hold it (never through vbw).
record_edit() {
  local f="${2:-.vbw/record.json}"
  jq "$1" "$f" > "$TEST_ROOT/edit.json" && cat "$TEST_ROOT/edit.json" > "$f"
}

# as_schema3 [FILE]: the record as the VBW before R150 wrote it: no protected
# field, and the schema its fields need under schemas 1 to 3.
as_schema3() {
  record_edit 'del(.protected)
    | .schema = (if has("recommendation") or any(.todos[]?; type == "object" and (has("sort") or has("size"))) then 3
                 elif any(.checks[]?; .alone == true) then 2 else 1 end)' "${1:-.vbw/record.json}"
}
