# shellcheck shell=bash
# Shared fixture builder for the requirement-fix tests (R160, R194). Load after helper:
#   load helper
#   load fix-helper
#   load fixture-helper
# and build each shape once per file: setup_file() { fixture_build NAME fix_project SHAPE; }.
#
# Every shape is a git project with R1 (pay) and R2 (refund) [auto], check C1
# (R1) running tests/c1.sh and check C2 (R2) running tests/c2.sh, one plan P1.1
# that writes src/pay.txt and src/refund.txt, approved:
#   planned  Planned and approved, nothing built (fix-regression-test).
#   built    "planned", then P1.1 built with the refund, marked done and proved
#            (a failed proof is allowed, as the tests' own built helper did).
#   shop     Adds R3 [human] with its own plan P1.2 (src/ui.txt) and the
#            src/staged.txt seed. Built and proved, then the user breaks the
#            payment and the next proof opens F_PROVE for R1 (fix-commit-own-checks).
#   shared   C1 and C2 both list tests/shared.sh, and the spec declares the
#            project command test. Built and proved, then F1 (a proof's fix for
#            R1, no source) and F2 (the test command's fix) are added by hand
#            (fix-run-own-checks).

# fix_edit_record JQ_EXPR: a hand edit of the record (the glance is dropped so
# readers take the record).
fix_edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

fix_project() {
  local shape=${1:-planned} spec phases plans checks
  case $shape in planned | built | shop | shared) ;; *) echo "fix_project: unknown shape '$shape'" >&2; return 1 ;; esac
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  case $shape in
    shop) spec='# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a refund\n- R3 [human] Paying feels safe\n' ;;
    shared) spec='# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a refund\n\n## Commands\n\n- test: sh tests/all.sh\n' ;;
    *) spec='# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a refund\n' ;;
  esac
  # shellcheck disable=SC2059 # the spec text above holds the newlines as \n
  printf "$spec" > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  case $shape in
    shared)
      printf 'true\n' > tests/shared.sh
      printf 'echo all\n' > tests/all.sh
      printf 'sh tests/shared.sh && grep -qx paid src/pay.txt\n' > tests/c1.sh
      printf 'sh tests/shared.sh && test -f src/refund.txt\n' > tests/c2.sh
      ;;
    *)
      printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
      printf 'test -f src/refund.txt\n' > tests/c2.sh
      ;;
  esac
  [ "$shape" != shop ] || printf 'three\n' > src/staged.txt
  case $shape in
    planned | built)
      phases='[{id: "P1", title: "Pay", reqs: ["R1", "R2"], goal: "Customers pay and get refunds", criteria: ["paid", "refunded"], tier: "standard"}]'
      plans='[{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1", "R2"], files: ["src/pay.txt", "src/refund.txt"], after: [], tasks: ["pay", "refund", "note"]}]'
      checks='[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
               {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}]'
      ;;
    shop)
      phases='[{id: "P1", title: "Pay", reqs: ["R1", "R2", "R3"], goal: "Customers pay and get refunds", criteria: ["paid"], tier: "standard"}]'
      plans='[{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1", "R2"], files: ["src/pay.txt", "src/refund.txt"], after: [], tasks: ["pay", "refund"]},
              {id: "P1.2", phase: "P1", title: "Feel", reqs: ["R3"], files: ["src/ui.txt"], after: [], tasks: ["calm words"]}]'
      checks='[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
               {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}]'
      ;;
    shared)
      phases='[{id: "P1", title: "Pay", reqs: ["R1", "R2"], goal: "Customers pay and get refunds", criteria: ["paid"], tier: "standard"}]'
      plans='[{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1", "R2"], files: ["src/pay.txt", "src/refund.txt"], after: [], tasks: ["pay", "refund"]}]'
      checks='[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh", "tests/shared.sh"]},
               {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh", "tests/shared.sh"]}]'
      ;;
  esac
  # The three parts above are jq program text, so they are spliced into the program.
  jq -nc "{phases: $phases, plans: $plans, checks: $checks,
    rules: [{req: \"R1\", text: \"a customer can pay\", check: \"C1\"}, {req: \"R2\", text: \"a refund is written\", check: \"C2\"}]}" | "$VBW" apply > /dev/null
  git add -A
  git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
  case $shape in
    planned) return 0 ;;
    built)
      printf 'paid\n' > src/pay.txt
      printf 'refund\n' > src/refund.txt
      "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
      # shellcheck disable=SC1010 # "done" is a vbw subcommand
      "$VBW" plan done P1.1 > /dev/null
      "$VBW" prove > /dev/null 2>&1 || true
      ;;
    shop)
      printf 'paid\n' > src/pay.txt
      printf 'refund\n' > src/refund.txt
      printf 'calm\n' > src/ui.txt
      "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
      "$VBW" commit P1.2 "feat(ui): calm" > /dev/null
      # shellcheck disable=SC1010 # "done" is a vbw subcommand
      "$VBW" plan done P1.1 > /dev/null
      # shellcheck disable=SC1010 # "done" is a vbw subcommand
      "$VBW" plan done P1.2 > /dev/null
      "$VBW" prove > /dev/null 2>&1 || { echo "the first proof failed"; return 1; }
      printf 'unpaid\n' > src/pay.txt
      git commit -q -am "feat(pay): a bug"
      "$VBW" prove > /dev/null 2>&1 || true
      F_PROVE=$(jq -r '[.fixes[] | select(.req == "R1" and .status == "open")][0].id // empty' .vbw/record.json)
      [ -n "$F_PROVE" ] || { echo "the proof opened no fix for R1"; jq .fixes .vbw/record.json; return 1; }
      export F_PROVE
      ;;
    shared)
      printf 'paid\n' > src/pay.txt
      printf 'refund\n' > src/refund.txt
      "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
      # shellcheck disable=SC1010 # "done" is a vbw subcommand
      "$VBW" plan done P1.1 > /dev/null
      "$VBW" prove > /dev/null 2>&1 || { echo "the proof failed"; return 1; }
      # F1 as vbw prove opens a fix (no source), F2 for the test command.
      fix_edit_record '.fixes += [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"},
                                  {id: "F2", command: "test", attempts: 0, status: "open", note: "test fail"}]'
      ;;
  esac
}
