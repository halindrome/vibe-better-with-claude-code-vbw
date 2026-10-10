# shellcheck shell=bash
# Records in format 4 (R150). Load after helper:
#   load helper
#   load protected-helper
#
# Every record this VBW writes is schema 4 and carries the protected list:
# every file an approved check protects (the union of all checks' files, each
# path once, in sorted order), right after lease, whatever the number of checks
# (an empty list when there are none). Records an older VBW wrote (schema 1, 2
# or 3, no list) are still read, and become schema 4 on their next write.

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
# src/pay.txt) and N checks C1..CN of R1 and R2 (N >= 1). Check K runs
# tests/cK.sh and lists tests/shared.sh then tests/cK.sh (the shared file is
# listed by every check, and the lists are not in sorted order); the last check
# lists no files. The check scripts are written too. The rules name C1, and C2
# when there is one (else C1 serves R2 as well, as a check of R1 cannot: with
# N = 1 the document has no rule for R2 and R2 has no check).
protected_doc() {
  local i
  for ((i = 1; i <= $1; i++)); do printf 'grep -qx paid src/pay.txt\n' > "tests/c$i.sh"; done
  printf 'true\n' > tests/shared.sh
  jq -nc --argjson n "$1" '{
    phases: [{id: "P1", title: "Pay", reqs: (if $n == 1 then ["R1"] else ["R1", "R2"] end), goal: "Customers pay and get refunds", criteria: ["src/pay.txt says paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: (if $n == 1 then ["R1"] else ["R1", "R2"] end), files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay", "refund", "note"]}],
    checks: [range(1; $n + 1) | {id: "C\(.)", req: (if . % 2 == 0 then "R2" else "R1" end), run: ["sh", "tests/c\(.).sh"]}
             + (if . == $n then {} else {files: ["tests/shared.sh", "tests/c\(.).sh"]} end)],
    rules: ([{req: "R1", text: "a customer can pay", check: "C1"}] + (if $n == 1 then [] else [{req: "R2", text: "a refund is paid back", check: "C2"}] end))}'
}

# protected_apply N [JQ_FILTER]: apply protected_doc N (through FILTER when given).
protected_apply() {
  protected_doc "$1" | jq -c "${2:-.}" | "$VBW" apply > /dev/null
}

# protected_union [FILE]: the union of the record's check files, sorted, each once.
protected_union() {
  jq -c '[.checks[].files // [] | .[]] | unique' "${1:-.vbw/record.json}"
}

# format4 [FILE]: the record is schema 4, its keys begin schema, lease,
# protected, checks, and protected is the union of its checks' files.
format4() {
  local f="${1:-.vbw/record.json}"
  jq -e '.schema == 4 and (keys_unsorted | .[:4]) == ["schema", "lease", "protected", "checks"]
    and .protected == ([.checks[].files // [] | .[]] | unique)' "$f" > /dev/null \
    || { echo "not format 4:"; jq -c '{schema, keys: (keys_unsorted | .[:5]), protected}' "$f"; return 1; }
}

# record_edit FILTER [FILE]: change the record by hand, as a restored or older
# project would hold it (never through vbw).
record_edit() {
  local f="${2:-.vbw/record.json}"
  jq "$1" "$f" > "$TEST_ROOT/edit.json" && cat "$TEST_ROOT/edit.json" > "$f"
}

# as_older [FILE]: the record as a VBW before format 4 wrote it: no protected
# list, and the schema its fields needed then (3 with a sorted todo or a stored
# recommendation, 2 with a check marked alone, else 1).
as_older() {
  record_edit 'del(.protected)
    | .schema = (if has("recommendation") or any(.todos[]?; type == "object" and (has("sort") or has("size")))
                 then 3 elif any(.checks[]?; .alone == true) then 2 else 1 end)' "${1:-.vbw/record.json}"
}
