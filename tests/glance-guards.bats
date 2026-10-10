#!/usr/bin/env bats
# R150 (decision D238; docs/guards.md): the Bash and file guards read the
# glance (.vbw/runtime/glance.json) with a normal jq parse while it is current,
# and .vbw/record.json otherwise: when the glance is missing, not a readable
# file, not JSON, lacks schema, lease or protected, or is not newer than the
# record (after git checkout, git reset or a hand edit, even within the same
# second). Both give identical answers in every state. A forged older glance
# changes nothing; under any run an agent's write of the glance is refused as a
# write of the record is; outside a VBW project a stray glance is ignored; no
# guard streams the record. L1.

load helper
load protected-helper
load glance-helper

setup() {
  vbw_setup
  glance_project
}

teardown() { vbw_teardown; }

# build_run: session s1's build run of P1.1 (it may write src/ and tests/).
build_run() { VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null; }

@test "R150: the guards and the doctor's guard self-test read the glance and never stream the record" {
  ! grep -n -- '--stream' "$PLUGIN_ROOT/hooks/hooks.json" "$PLUGIN_ROOT/lib/cmd-doctor.sh" "$PLUGIN_ROOT"/hooks/*.jq \
    || { echo "--stream remains"; false; }
  ! grep -vE '^[[:space:]]*#' "$PLUGIN_ROOT/hooks/common.jq" | grep -nE 'fromstream|tostream|truncate_stream|_events|skip_key|split_next' \
    || { echo "common.jq still reads the record as events"; false; }
  local tool cmd
  for tool in Bash Write Read; do
    cmd=$(jq -r --arg t "$tool" '[.hooks.PreToolUse[] | select(.matcher as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json")
    [[ "$cmd" == *'.vbw/runtime/glance.json'* ]] || { echo "the $tool guard does not read the glance: $cmd"; false; }
  done
  grep -q 'glance\.json' "$PLUGIN_ROOT/lib/cmd-doctor.sh" || { echo "the doctor's guard self-test does not read the glance"; false; }
}

@test "R150: while the glance is current the guards answer from it alone, without reading the record" {
  build_run
  glance_current
  # An unreadable record, older than the glance: only the glance can give these answers.
  printf 'not json' > .vbw/record.json
  touch -t 202001010000 .vbw/record.json
  glance_current
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)")
  denied_with "is a protected check file"
  ANSWER=$(hook_answer "$PROJECT" "$(bash_in 'printf x > README.md' workflow-subagent)")
  denied_with "outside this run's files"
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write src/pay.txt workflow-subagent)")
  allowed
}

@test "R150: a missing, unreadable, incomplete or older glance gives the answers of the record" {
  build_run
  local good="$TEST_ROOT/good.json" v
  cp "$GLANCE" "$good"
  for v in missing directory unreadable notjson empty nolease noprotected noschema older; do
    rm -rf "$GLANCE"
    case $v in
      missing) ;;
      directory) mkdir "$GLANCE" ;;
      unreadable)
        [ "$(id -u)" != 0 ] || continue
        cp "$good" "$GLANCE"
        chmod 000 "$GLANCE"
        ;;
      notjson) printf '{"schema": 4, "lease": nu' > "$GLANCE" ;;
      empty) : > "$GLANCE" ;;
      nolease) jq 'del(.lease)' "$good" > "$GLANCE" ;;
      noprotected) jq 'del(.protected)' "$good" > "$GLANCE" ;;
      noschema) jq 'del(.schema)' "$good" > "$GLANCE" ;;
      older) jq '.lease = null | .protected = []' "$good" > "$GLANCE" ;;
    esac
    # Newer than the record, except the older one: only what the file holds rules it out.
    if [ "$v" = older ]; then touch -t 202001010000 "$GLANCE"; elif [ -e "$GLANCE" ]; then touch -t 203001010000 "$GLANCE"; fi
    like_record "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)" || { echo "glance: $v"; false; }
    denied_with "is a protected check file" || { echo "glance: $v"; false; }
    like_record "$PROJECT" "$(bash_in 'printf x > tests/shared.sh' workflow-subagent)" || { echo "glance: $v"; false; }
    denied_with "is a protected check file" || { echo "glance: $v"; false; }
    like_record "$PROJECT" "$(file_in Write README.md workflow-subagent)" || { echo "glance: $v"; false; }
    denied_with "outside this run's files" || { echo "glance: $v"; false; }
    like_record "$PROJECT" "$(file_in Write src/pay.txt workflow-subagent)" || { echo "glance: $v"; false; }
    allowed || { echo "glance: $v"; false; }
    [ -d "$GLANCE" ] || chmod 644 "$GLANCE" 2> /dev/null || true
  done
}

# The working record: a build run of four checks (tests/c3.sh protected too);
# the committed one has no run and three checks. Each case starts from the
# working record with a current glance.
working() {
  cp "$TEST_ROOT/working.json" .vbw/record.json
  "$VBW" decide "Back to the working record" > /dev/null
  glance_current
  jq -e '.lease.kind == "build" and (.protected | index("tests/c3.sh") != null)' "$GLANCE" > /dev/null
}

# same_second: the record's time becomes the glance's own, as when both change within one second.
same_second() { touch -r "$GLANCE" .vbw/record.json; }

@test "R150: after git checkout, git reset or a hand edit within the glance's second, the guards answer from the record" {
  protected_doc 4 | jq -c '.plans[0].files = ["src/", "tests/"]' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  build_run
  cp .vbw/record.json "$TEST_ROOT/working.json"

  # git checkout: the committed record, with no run and tests/c3.sh not protected.
  working
  git checkout -- .vbw/record.json
  same_second
  like_record "$PROJECT" "$(file_in Write tests/c3.sh workflow-subagent)"
  allowed
  like_record "$PROJECT" "$(file_in Write README.md workflow-subagent)"
  allowed

  # git reset --hard: the same.
  working
  git reset -q --hard
  same_second
  like_record "$PROJECT" "$(bash_in 'printf x > tests/c3.sh' workflow-subagent)"
  allowed

  # A hand edit in place that narrows the run's files (a changed lease).
  working
  record_edit '.lease.files = ["src/"]'
  same_second
  like_record "$PROJECT" "$(file_in Write tests/new_test.sh workflow-subagent)"
  denied_with "outside this run's files"

  # A hand edit saved as a new file that drops tests/c3.sh from the list (a changed protected list).
  working
  jq '.protected -= ["tests/c3.sh"]' .vbw/record.json > "$TEST_ROOT/edited.json"
  mv "$TEST_ROOT/edited.json" .vbw/record.json
  same_second
  like_record "$PROJECT" "$(file_in Write tests/c3.sh workflow-subagent)"
  allowed
  like_record "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)"
  denied_with "is a protected check file"
}

# matrix: every input gives the same answer from the current glance and from the record.
matrix() {
  local input
  for input in \
    "$(file_in Write tests/c1.sh workflow-subagent)" \
    "$(file_in Edit tests/shared.sh workflow-subagent)" \
    "$(bash_in 'printf x > tests/c2.sh' workflow-subagent)" \
    "$(file_in Write README.md workflow-subagent)" \
    "$(bash_in 'printf x > README.md' workflow-subagent)" \
    "$(file_in Write src/pay.txt workflow-subagent)" \
    "$(file_in Write tests/c1.sh)" \
    "$(file_in Write src/pay.txt)" \
    "$(file_in Read .env workflow-subagent)" \
    "$(file_in Read .env)" \
    "$(file_in Write .vbw/record.json workflow-subagent)" \
    "$(file_in Write .vbw/record.json)" \
    "$(bash_in 'cp backup.json .vbw/record.json')" \
    "$(file_in Write .git/vbw/consent.json)" \
    "$(file_in Write src/pay.txt "" s2)" \
    "$(file_in Write src/pay.txt workflow-subagent s2)" \
    "$(bash_in 'printf x > src/pay.txt' "" s2)"; do
    both "$PROJECT" "$input" || { echo "state: $1"; return 1; }
  done
}

@test "R150: the guards give identical answers from the glance and from the record in every state" {
  matrix "no run"
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)")
  allowed
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  matrix "plan run"
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  build_run
  matrix "build run"
  both "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)"
  denied_with "is a protected check file"
  both "$PROJECT" "$(file_in Write README.md workflow-subagent)"
  denied_with "outside this run's files"
  both "$PROJECT" "$(file_in Write src/pay.txt "" s2)"
  denied_with "another session"
  both "$PROJECT" "$(file_in Write .vbw/record.json workflow-subagent)"
  denied_with ".vbw/record.json is written only by vbw"
  both "$PROJECT" "$(file_in Read .env)"
  denied_with "may hold secrets"
  both "$PROJECT" "$(file_in Write .git/vbw/consent.json)"
  denied_with "the consent file is written only by /vbw:approve"
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  "$VBW" qa finding R1 "Payment fails" > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start fix F1 > /dev/null
  matrix "fix run"
  both "$PROJECT" "$(bash_in 'printf x > tests/c2.sh' workflow-subagent)"
  denied_with "is a protected check file"
}

@test "R150: a forged glance with an empty protected list or no lease, older than the record, changes no answer" {
  build_run
  local good="$TEST_ROOT/good.json" forged
  cp "$GLANCE" "$good"
  for forged in '.protected = []' 'del(.lease)' '.lease = null' '.protected = [] | .lease = null'; do
    jq "$forged" "$good" > "$GLANCE"
    touch -t 202001010000 "$GLANCE"
    ANSWER=$(hook_answer "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)")
    denied_with "is a protected check file" || { echo "forged: $forged"; false; }
    ANSWER=$(hook_answer "$PROJECT" "$(bash_in 'printf x > tests/shared.sh' workflow-subagent)")
    denied_with "is a protected check file" || { echo "forged: $forged"; false; }
    ANSWER=$(hook_answer "$PROJECT" "$(file_in Write README.md workflow-subagent)")
    denied_with "outside this run's files" || { echo "forged: $forged"; false; }
  done
}

# glance_refused: every way an agent writes the glance is refused, saying only vbw writes it.
glance_refused() {
  local input
  for input in \
    "$(file_in Write .vbw/runtime/glance.json workflow-subagent)" \
    "$(file_in Edit .vbw/runtime/glance.json workflow-subagent)" \
    "$(file_in MultiEdit .vbw/runtime/glance.json workflow-subagent)" \
    "$(bash_in 'printf "{}" > .vbw/runtime/glance.json' workflow-subagent)" \
    "$(bash_in 'cp forged.json .vbw/runtime/glance.json' workflow-subagent)" \
    "$(bash_in 'tee .vbw/runtime/glance.json < forged.json' workflow-subagent)" \
    "$(bash_in 'sed -i.bak s/build/none/ .vbw/runtime/glance.json' workflow-subagent)" \
    "$(bash_in "$(printf 'python3 - <<%s\nopen(".vbw/runtime/glance.json", "w").write("{}")\nEOF' "'EOF'")" workflow-subagent)"; do
    ANSWER=$(hook_answer "$PROJECT" "$input")
    denied_with ".vbw/runtime/glance.json is written only by vbw (vbw help lists the commands)" || { echo "run: $1; input: $input"; return 1; }
  done
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write .vbw/record.json workflow-subagent)")
  denied_with ".vbw/record.json is written only by vbw (vbw help lists the commands)"
}

@test "R150: under any run an agent's write of the glance is refused as a record write is; the main conversation outside a run is not" {
  local kind
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write .vbw/runtime/glance.json)")
  allowed
  ANSWER=$(hook_answer "$PROJECT" "$(bash_in 'printf "{}" > .vbw/runtime/glance.json')")
  allowed
  for kind in plan qa map build fix; do
    case $kind in
      build) VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null ;;
      fix)
        "$VBW" qa finding R1 "Payment fails" > /dev/null
        VBW_SESSION_ID=s1 "$VBW" run start fix F1 > /dev/null
        ;;
      *) VBW_SESSION_ID=s1 "$VBW" run start "$kind" > /dev/null ;;
    esac
    glance_refused "$kind"
    VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  done
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write .vbw/runtime/glance.json)")
  allowed
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Edit .vbw/runtime/glance.json)")
  allowed
}

@test "R150: outside a VBW project the guards give no answer and print no error, with or without a stray glance" {
  local d="$TEST_ROOT/plain project" input stray
  mkdir -p "$d"
  cd "$d"
  vbw_git_project
  mkdir -p .vbw/runtime tests
  for stray in no yes; do
    if [ "$stray" = yes ]; then
      jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{schema: 4, project: {name: "stray"}, milestone: null, settings: {},
        lease: {run: "build-1", kind: "build", session: "s1", started_at: $t, files: ["src/"]},
        protected: ["tests/c1.sh"], requirements: [], plans: []}' > "$GLANCE"
      touch -t 203001010000 "$GLANCE"
    fi
    for input in \
      "$(file_in Write tests/c1.sh workflow-subagent)" \
      "$(file_in Write README.md workflow-subagent)" \
      "$(bash_in 'printf x > tests/c1.sh' workflow-subagent)" \
      "$(bash_in 'git reset --hard')" \
      "$(file_in Read .env)" \
      "$(file_in Write src/a.txt "" s2)"; do
      # shellcheck disable=SC2034 # read by allowed
      ANSWER=$(hook_answer "$d" "$input") || { echo "stray glance: $stray"; false; }
      allowed || { echo "stray glance: $stray; input: $input"; false; }
    done
  done
}

@test "R150: vbw doctor's guard self-test passes with a current glance and with none" {
  build_run
  glance_current
  run "$VBW" doctor
  [[ "$output" == *"the guards work"* ]] || { echo "$output"; false; }
  rm -f "$GLANCE"
  run "$VBW" doctor
  [[ "$output" == *"the guards work"* ]] || { echo "$output"; false; }
}
