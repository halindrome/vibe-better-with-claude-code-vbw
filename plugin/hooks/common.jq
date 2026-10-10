# Shared by the PreToolUse guards (docs/guards.md). Each guard runs as jq
# itself (build plan K20), with --stream and --arg root "$CLAUDE_PROJECT_DIR".
# Its inputs, in order: the hook input (stdin); $CLAUDE_PROJECT_DIR/.vbw/record.json,
# which jq skips when it does not exist; hooks/end.json, the sentinel
# "vbw-guard-end". So after the hook input, the next input is the record (a VBW
# project), the sentinel (not one), or a parse error (a corrupt record: still a
# VBW project).
#
# --stream hands the inputs over as events, so a guard reads the hook input in
# full and only the beginning of the record (R149, R150): the record writer puts
# schema, lease and then the protected check files first, and the guard stops at
# the first other key, whatever the record's size. Format 4 (more than 50
# checks) carries the top-level key "protected", the list of every protected
# check file: the guard reads it and stops there, never reading an event of
# checks. Format 3 (50 checks or fewer) has no protected key: the guard reads
# its checks, which come right after the lease and are small. A record with its
# keys in another order, or a larger one an older VBW wrote (until its next
# write), is read on until the lease, and the checks when they matter, are
# complete, or the file ends: the same answer, only slower.
#
# Membership tests are anchored regexes, not array literals: they compile to far
# fewer jq instructions, and compiling is most of a guard's cost.

# The events of the hook input, up to the one that closes its top-level value.
def hook_events: [label $l | inputs | ., (select((.[0] | length) == 0 or (length == 1 and (.[0] | length) == 1)) | break $l)];

# What follows the events of one top-level key: [values, next], next being the
# event after them (null at the end of the input). A generator of values and the
# event that ends them, as {next: EVENT}, becomes that pair.
def split_next: if (last | type) == "object" and (last | has("next")) then [.[:-1], last.next] else [., null] end;

# The lease: the leaf events of the top-level key "lease" (the first is $head).
def lease_events($head):
  [$head, (label $l | inputs | if .[0][0] == "lease" then select(length == 2) else ({next: .}, break $l) end)] | split_next;

# The protected check files: the events of the list under the top-level key
# "protected" ($head is the first; an empty list is that one event). It stops at
# the event that closes the list and never pulls the one after it, which belongs
# to the checks.
def protected_events($head):
  if ($head[0] | length) == 1 then [$head]
  else [$head, (label $l | inputs | ., (select(length == 1 and (.[0] | length) == 2) | break $l))] end;

# The checks: the paths of their files, all a guard reads (leaf events of
# "checks" whose path has "files" third; closing events carry no value, so null
# is dropped). The first event is $head.
def check_files($head):
  [($head | select(.[0][2] == "files") | .[1]), (label $l | inputs | if .[0][0] != "checks" then ({next: .}, break $l) elif .[0][2] == "files" then .[1] else empty end)]
  | split_next | .[0] |= map(select(. != null));

# The events after the key $k, up to the one that follows them (null at the end).
def skip_key($k): first((inputs | select((.[0] | length) == 0 or .[0][0] != $k)), null);

# The lease and checks of the record, from the events after the hook input. The
# input is read key by key: the lease is rebuilt from its leaf events at once
# (cheaper than setting each path as it arrives), the checks are reduced to one
# entry holding every protected file, and any other key is skipped.
# $agent: the call comes from a subagent; $writes: it may write a file. Only
# then does a build or fix lease need the checks (protected check files).
def read_events($e; $rec; $agent; $writes):
  if $e == null or ($e[0] | length) == 0 then $rec
  elif ($rec | has("lease"))
       and ((($agent and $writes and ($rec.lease | type) == "object" and (($rec.lease.kind // "") | test("^(build|fix)$"))) | not)
            or ($rec | has("checks"))) then $rec
  elif $e[0][0] == "lease" then
    lease_events($e) as [$evs, $next]
    | read_events($next; $rec + {lease: ([fromstream($evs[], [["lease"]])][0].lease)}; $agent; $writes)
  elif $e[0][0] == "protected" then
    protected_events($e) as $evs
    | read_events(if $rec | has("lease") then null else first(inputs, null) end;
        $rec + {checks: [{files: ([fromstream($evs[], [["protected"]])][0].protected // [])}]}; $agent; $writes)
  elif $e[0][0] == "checks" then
    check_files($e) as [$files, $next]
    | read_events($next; $rec + {checks: [{files: $files}]}; $agent; $writes)
  else read_events(skip_key($e[0][0]); $rec; $agent; $writes) end;

def read_record($agent; $writes):
  (try input catch null) as $first
  | if $first == null then {project: true, record: {}}
    elif ($first[0] | length) == 0 then {project: ($first[1] != "vbw-guard-end"), record: {}}
    else
      try {project: true, record: read_events($first; {}; $agent; $writes)}
      catch {project: true, record: {}}
    end;

# {hook, project, record, lease, foreign}: foreign is the open run lease (under
# 24 hours, with an owning session) when the hook input comes from a different
# session, main conversation or agent alike (D11), else null. lease is the active run lease when this call
# comes from a subagent (the hook input names an agent_type) during a run of
# at most 24 hours (docs/workflows.md), else null. The main session is never
# held to a lease. WRITES, run on the hook input: whether the call may write a file.
def guard_context(writes):
  (hook_events | fromstream(.[])) as $hook
  | read_record(($hook.agent_type // "") != ""; $hook | writes) as $r
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
def consent_path: test("(^|/)vbw/consent\\.json$");

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
  elif $lease.files == [] then
    "\(.) cannot be written during a \($lease.kind) run: its agents only read"
  elif $lease.kind == "plan" and test_path then empty
  elif $lease.files != null and (. as $p | any($lease.files[]; covers($p)) | not) then
    "\(.) is outside this run's files (\($lease.files | join(", "))): agents write only their plan's files"
  elif ($lease.kind | test("^(build|fix)$")) and (. as $p | any($record.checks[]?.files[]?; . == $p)) then
    "\(.) is a protected check file: the contract is fixed while building"
  else empty end;

# Why another session may not write PATH (project-relative) while FOREIGN's run
# is open, or empty: it writes lease.files (null: any project file, []: none).
def foreign_denial($f):
  . as $p | select($p != null and (($f.files // [$p]) | any(.[]; covers($p))))
  | "\($p) is being written by run \($f.run) of another session (\($f.session)): wait for it; if the user says that session is closed, they run vbw run end --owner-closed";

def secret_reason: "\(basename) may hold secrets; VBW never reads or writes secret files";
def record_reason: ".vbw/record.json is written only by vbw (vbw help lists the commands)";
def consent_reason: "the consent file is written only by /vbw:approve";

# A reason string becomes the hook's deny decision.
def deny: {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("VBW guard: " + .)}};
