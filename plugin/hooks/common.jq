# Shared by the PreToolUse guards (docs/guards.md). Each guard runs as jq
# itself (build plan K20), with --arg root "$CLAUDE_PROJECT_DIR" and
# --rawfile glance F. Its inputs, in order: the hook input (stdin);
# $CLAUDE_PROJECT_DIR/.vbw/record.json, which jq skips when it does not exist;
# hooks/end.json, the sentinel "vbw-guard-end". So after the hook input, the
# next input is the record (a VBW project), the sentinel (not one), or a parse
# error (a corrupt record: still a VBW project).
#
# The guard has two sources for the schema, lease and protected check files
# (R150). The glance (.vbw/runtime/glance.json, decision D238) is a small file
# the kernel rewrites with every record write; the hook command passes it as
# $glance only when the record exists and the glance is a readable regular file
# strictly newer than the record, else $glance is empty. When $glance parses to
# an object holding schema, lease and protected, the guard uses it and never
# reads the record input. Otherwise it reads the record with one plain input,
# whatever its size: the glance was missing, stale, forged older or damaged.
# Both give the same answers. A record that cannot be parsed counts as a VBW
# project with no lease, except during a run: the hook command passes
# --arg open 1 while .vbw/runtime/run-open exists, and then the guard fails
# (R165), which the hook command turns into a block.
#
# Membership tests are anchored regexes, not array literals: they compile to far
# fewer jq instructions, and compiling is most of a guard's cost.

# The glance as an object when it holds schema, lease and protected, else null.
def glance_object:
  (try fromjson catch null) | select(type == "object" and has("schema") and has("lease") and has("protected"));

# {project, record}: from the current glance, else from the record input.
def read_record:
  ([$glance | glance_object][0]) as $gl
  | if $gl != null then {project: true, record: $gl}
    else (try input catch "vbw-guard-corrupt") as $rec
      | if $rec == "vbw-guard-corrupt" and ($ARGS.named.open // "") == "1" then error("the record cannot be parsed during a run") else . end
      | {project: ($rec != "vbw-guard-end"), record: (if $rec | type == "object" then $rec else {} end)}
    end;

# {hook, project, record, lease, foreign}: foreign is the open run lease (under
# 24 hours, with an owning session) when the hook input comes from a different
# session, main conversation or agent alike (D11), else null. lease is the active run lease when this call
# comes from a subagent (the hook input names an agent_type) during a run of
# at most 24 hours (docs/workflows.md), else null. The main session is never
# held to a lease.
def guard_context(writes):
  input as $hook
  | read_record as $r
  | ($r.record) as $record
  | (($record.lease | select(type == "object" and (try (now - (.started_at | fromdateiso8601) < 86400) catch false))) // null) as $live
  | {hook: $hook, project: $r.project, record: $record,
     lease: (if ($hook.agent_type // "") != "" then $live else null end),
     foreign: (($live | select((.session // "") != "" and ($hook.session_id // .session) != .session)) // null)};

def basename: split("/") | last // "";
def secret_path: basename
  | (test("^\\.env(\\..+)?$") and (test("^\\.env\\.(example|sample|template|dist|defaults)$") | not))
    or test("\\.(pem|key|p12|pfx|kdbx|keystore|jks)$|^id_(rsa|dsa|ecdsa|ed25519)$|^\\.(netrc|pgpass|npmrc|pypirc)$|^credentials(\\.json)?$");
def record_path: test("(^|/)\\.vbw/record\\.json$");
def glance_reason: ".vbw/runtime/glance.json is written only by vbw (vbw help lists the commands)\nNext: leave it as it is; vbw rewrites it with every change to the record";
def glance_path: test("(^|/)\\.vbw/runtime/glance\\.json$");
def consent_path: test("(^|/)vbw/(consent|runs)\\.json$");

# PATH (relative to $cwd unless absolute) as a project-relative path, or null
# when it lies outside $root. "." and ".." segments are resolved.
def project_path($cwd; $root):
  (if startswith("/") then . else "\($cwd)/\(.)" end)
  | reduce (split("/")[] | select(. != "" and . != ".")) as $s ([];
      if $s == ".." then .[:-1] else . + [$s] end)
  | "/" + join("/")
  | if startswith(($root | rtrimstr("/")) + "/") then .[($root | rtrimstr("/") | length) + 1:] else null end;

# A plan file entry covers PATH: the same path, or a directory entry (ending
# in /) with PATH under it.
def covers($p): . as $e | $e == $p or (($e | endswith("/")) and ($p | startswith($e)));

# PATH (project-relative) is a test file, by place or by name: the one
# definition of what a planning run may write besides .vbw/ (R75).
def test_path: test("(^|/)(tests?|spec|__tests__)/") or (basename | test("\\.test\\.|_test\\.|^test_.*\\.py$"));

# Why a subagent may not write PATH (project-relative) under LEASE, or empty.
def lease_write_denial($lease; $record):
  if . == null then empty
  elif glance_path then glance_reason
  elif $lease.files == [] then
    "\(.) cannot be written during a \($lease.kind) run: its agents only read\nNext: leave \(.) as it is; report the change you need in your result for the session that started the run"
  elif $lease.kind == "plan" and test_path then empty
  elif $lease.new_tests == true and (. as $p | any($lease.editable[]?; . == $p)) then empty
  elif $lease.new_tests == true and (. as $p | any($record.protected[]?; . == $p)) then
    "\(.) is a protected check file of another requirement: the fix may edit only the check files of its own requirement (\($lease.editable | join(", ")))\nNext: leave \(.) as it is; put the regression test in a new test file and register it with vbw fix check"
  elif $lease.new_tests == true and test_path then empty
  elif $lease.files != null and (. as $p | any($lease.files[]; covers($p)) | not) then
    "\(.) is outside this run's files (\($lease.files | join(", "))): agents write only their plan's files\nNext: leave \(.) as it is; report that the plan needs it, so the plan can be replanned with vbw apply"
  elif ($lease.kind | test("^(build|fix)$")) and ($record | has("protected") | not) then
    "\(.) cannot be written: this project's record was not saved by this VBW yet, so its protected check files are unknown; end the run and start it again, which saves the record\nNext: tell the session that started the run to end it (vbw run end) and start it again"
  elif ($lease.kind | test("^(build|fix)$")) and (. as $p | any($record.protected[]?; . == $p)) then
    "\(.) is a protected check file: the contract is fixed while building\nNext: leave \(.) as it is; if the check is wrong, report it so the user can change the contract"
  else empty end;

# Why a subagent may not write ORIGINAL (the path as given), which lies outside
# the project, during a run, naming where the run may write instead (R177).
def outside_denial($lease):
  (if $lease.files == [] then "nothing: its agents only read"
   elif $lease.kind == "plan" then "the project's test files and .vbw/"
   elif $lease.files == null then "project files"
   else "its plan files (\($lease.files | join(", ")))" end) as $where
  | "\(.) is outside the project: during a \($lease.kind) run agents write only inside it, and there only \($where)\nNext: write inside the project folder instead, or put scratch work in .vbw/runtime/";

# Why a subagent may not write ORIGINAL (the path as given) under LEASE: a
# path outside the project is denied (R177), one inside goes to the lease rules.
def run_write_denial($g):
  . as $o | project_path($g.hook.cwd // $root; $root) as $p
  | if $p == null then (if $o | test("^/dev/(null|stdout|stderr|tty)$") then empty else $o | outside_denial($g.lease) end) else $p | lease_write_denial($g.lease; $g.record) end;

# Why another session may not write PATH (project-relative) while FOREIGN's run
# is open, or empty: it writes lease.files (null: any project file, []: none).
def foreign_denial($f):
  . as $p | select($p != null and (($f.files // [$p]) | any(.[]; covers($p))))
  | "\($p) is being written by run \($f.run) of another session (\($f.session)): wait for it; if the user says that session is closed, they run vbw run end --owner-closed\nNext: work on files outside \($f.files // ["the project"] | join(", ")) meanwhile, or wait until run \($f.run) ends";

def secret_reason: "\(basename) may hold secrets; VBW never reads or writes secret files\nNext: do not open \(basename); ask the user for the value you need, or use an example file such as .env.example";
def record_reason: ".vbw/record.json is written only by vbw (vbw help lists the commands)\nNext: run the vbw command that makes this change (vbw help lists them); read the record with vbw show or vbw status";
def consent_reason: "the consent file is written only by /vbw:approve, and the store of recorded runs (vbw/runs.json) only by vbw\nNext: the user approves through the approval menu (vbw next asks); leave the run store alone, vbw rewrites it by itself";

# A reason string becomes the hook's deny decision.
def deny: {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("VBW guard: " + .)}};
