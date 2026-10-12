# Guards

VBW's hooks (`plugin/hooks/hooks.json`) stop the few tool calls that would do
lasting harm, and say why. They are guard rails for an autonomous model, not a
sandbox: a determined program can always write a script and run it. The Claude
Code sandbox and permission rules remain the security boundary.

## What is denied

Every block ends with `Next: ` and says what to do instead, for
example `Next: leave src/x.js as it is; report that the plan needs it, so the
plan can be replanned with vbw apply`. The list of refusal kinds and their next
steps is in docs/workflows.md ("Every refusal and its next step").

**Everywhere** (any project, VBW or not):

| Call | Why |
|---|---|
| `vbw approve`, however it is spelled (`"$X/bin/vbw" approve`, `bash bin/vbw approve`, inside `$(...)` or `sh -c`) | Approving the contract is the user's decision: `/vbw:approve` |
| Writing the consent file (`<git-dir>/vbw/consent.json`) by redirect, by a non-reading program, or with a file tool | The same |
| Writing the store of recorded runs (`<git-dir>/vbw/runs.json`, the read lists that decide which check results are reused) the same ways | A forged read list could make a check pass without running; only the kernel writes it |

Naming the approval command in text (a commit message, `echo`, `grep`, a doc)
is not approving: only a command the shell would actually run is refused.

**Approving by answer.** The approval question (docs/proof.md) is answered in
Claude Code's own interface. A `PostToolUse` hook on `AskUserQuestion`
(`hooks/approve-answer.jq` and `hooks/approve-answer.sh`) runs after the user
answers. It acts only on a question named `Approve contract <12 hex>?`, and
only when the answer is exactly `Approve`; it then runs
`vbw approve --hash <fingerprint>` for that contract. Any other answer
(`Not yet`, or the user's own words) approves nothing and goes back to Claude
as what to change. Before the question is shown, a `PreToolUse` hook on
`AskUserQuestion` (`hooks/approve-ask.jq` and `hooks/approve-ask.sh`) adds
`Approve contract <12 hex>?` in front of an Approve / Not yet menu Claude asked
without it, while a contract waits for approval; other questions, a subagent's
questions and a question that already names a fingerprint are left as they are. The rewritten
question is shown to you as usual and you answer it: the hook never answers it
for you.

The model cannot approve through it. The hook sees only what the user
answered: Claude Code reports an answer to `PostToolUse` only after the user
gives it, so nothing the model writes can stand in for it. A question asked by
a subagent never counts. The guard above still refuses the model's own
`vbw approve`, so the answer hook is the only route besides the user typing
`/vbw:approve`.

**Cost does not grow with history.** A guard needs only three things from the
record: `schema`, `lease` and `protected` (the protected check files, one short
list in schema 4; it never reads the `checks`). While
`.vbw/runtime/glance.json` is current, that is newer than the record, the guard
reads those three from it with a normal parse, so it costs the same on a record
of 10 KB or 10 MB. The kernel keeps the glance newer with every record write
(docs/record.md). The guard reads `.vbw/record.json` instead when the glance is
missing, unreadable, lacks one of the three fields or is not newer (after
`git checkout`, `git reset`, a hand edit or a failed glance write). The answers
are the same; only the cost differs. The glance is never the source of truth.

## When a guard fails

A guard can fail: it crashes, cannot start (`jq` or the guard's file is missing
or unreadable), or runs past its time limit. What happens depends on where the
call happens:

| Where | What happens |
|---|---|
| During a run (`.vbw/runtime/run-open` exists; the kernel keeps it with the glance) | The call is **blocked**. Claude sees `VBW guard: the guard failed while a run is open, so this call is blocked. Next: run vbw doctor to see why, then retry` (exit status 2). The same holds when the guard must read `.vbw/record.json` and cannot parse it |
| In a VBW project with no open run | The call goes through, silently, as before |
| Outside a VBW project | Nothing changes and nothing is printed |

During a run the guard fails closed: a broken guard never lets a call through.
Nothing ever answers allow.

**Time limit.** A guard may use 5 seconds of CPU time, set with the shell's own
`ulimit -t 5` at the start of the hook command. Past that the shell stops the
guard, and the call is treated as a failed guard (blocked during a run). A
healthy guard takes a few milliseconds, so waiting on a busy machine does not
count: only CPU time does.

**If you are blocked.** Claude's own Bash calls may be blocked too, so run the
check yourself in a terminal, in the project folder:

```
vbw doctor
```

It reports what is wrong (for example `jq` missing) with the fix for each item
(docs/diagnostics.md). Fix it, then ask Claude to retry. If you cannot fix it
and want the run gone, `vbw run end` closes it (docs/workflows.md).

**In VBW projects** (the session's project directory, `$CLAUDE_PROJECT_DIR`,
holds `.vbw/record.json`; a corrupt record still counts):

| Call | Why |
|---|---|
| `rm -r` of `/`, `~`, `$HOME`, `.`, `..`, `*`, `.git` or `.vbw` | Destroys work |
| `git push` with `--force`, `--force-with-lease`, `--mirror`, `--delete`, `+ref` or `:ref` | Rewrites or deletes remote history |
| `git reset --hard`, `git clean -f`, `git checkout`/`git restore` of the whole tree (`.`, `*`, `:/`; `restore --staged` alone is fine), `git branch -D`, `git stash drop`/`clear`, `filter-branch`, `filter-repo`, `update-ref -d`, `reflog expire`/`delete` | Discards work git cannot give back |
| Reading or writing secret files: `.env` and `.env.*` (except `.example`, `.sample`, `.template`, `.dist`, `.defaults`), `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.kdbx`, `*.keystore`, `*.jks`, `id_rsa`/`id_dsa`/`id_ecdsa`/`id_ed25519`, `.netrc`, `.pgpass`, `.npmrc`, `.pypirc`, `credentials` | VBW never handles secrets. `ls`, `stat` and `test` on them are fine |
| Writing `.vbw/record.json` (file tools, redirects, any program that is not a reader such as `cat`, `jq`, `grep` or `git`) | Only `vbw` writes the record, validated |

**During a run** (`record.lease`, docs/workflows.md), any **subagent** (the hook
input names an `agent_type`) is also held to the lease. The main session never is.

| Call | Why |
|---|---|
| Writing a project file outside `lease.files` (file tools, shell redirects; paths resolved, `..` included) | Builders write only their plan's files |
| Writing any path outside the project folder (file tools, shell redirects, programs that write files; `/tmp` included; `/dev/null`, `/dev/stdout`, `/dev/stderr` and `/dev/tty` excepted) | A run writes only inside the project, and there only where the lease allows: nothing for a read-only run, the project's test files and `.vbw/` while planning, the plan's files while building. The refusal says so and ends with `Next: write inside the project folder instead, or put scratch work in .vbw/runtime/scratch/`; for a read-only run it ends with `Next: leave it; report what you needed in your result, this run's agents write nothing` |
| During `plan`, writing a project file that is neither under `.vbw/` nor a test file (`tests/`, `test/`, `spec/` or `__tests__/` folders; `*.test.*`, `*_test.*`, `test_*.py`) | Planning writes the spec, plans and tests, never product code |
| Writing `.vbw/runtime/glance.json` | Under any run, an agent's write is refused: only `vbw` writes the glance, like the record |
| Writing under `.vbw/runtime/scratch/` during a run | Allowed under `plan`, `build` and `fix`: the agents' one scratch folder for debugging scripts and logs, ignored by git and never read by a proof (agents create it). A read-only run (QA, mapping) still writes nothing, and under `build` or `fix` the rest of `.vbw/runtime/` stays refused as outside the run's files |
| Writing a protected check file (any check's `files`) during `build` or `fix` | The contract is fixed while building. The Lead runs the project's formatter and linter on check files before approval, and Devs format only their own files, so a formatter never changes an approved file |
| Writing a protected check file during a `fix` run for a QA finding | Allowed for the check files of the finding's requirement, and a new test file may be created; both wait for one approval before the proof (docs/proof.md). A check file of any other requirement stays protected, and the refusal ends with `Next: put the regression test in a new test file and register it with vbw fix check`. Fix runs for a failed proof stay fully protected |
| Under `build` or `fix`, an agent's file write on a record of schema 1 to 3, which has no `protected` list | The guard cannot tell which files are protected, so it refuses until the record is saved by this VBW as schema 4. Run any `vbw` command that writes the record (such as `/vbw:vibe`) from the main session, then retry |
| `git commit`, `push`, `rebase`, `merge`, `pull`, `cherry-pick`, `revert`, `am` | Commits go through `vbw commit`, with provenance |
| `git stash` (except `list`, `show`), `switch`, `reset`, `checkout` of a branch; `git checkout -- PATH` or `git restore PATH` outside `lease.files` | Agents share one working tree: nothing may move HEAD or other agents' changes |

**Programs that write files.** During a run, a subagent's `python`, `node`,
`deno`, `bun`, `perl`, `ruby`, `php` or `lua` command is judged like a shell
write: a file it writes outside `lease.files` gets the same refusal, naming the
path. The guard reads the paths the program text names as string literals
(`open('src/a.py', 'w')`, `Path('a').write_text`, `fs.writeFileSync('a', ...)`,
`File.write`, `os.remove`, `shutil.copy` and similar), in `-c`/`-e` code and in
a script given by heredoc (`python3 - <<'EOF'`), and the files given to
`perl -i`/`ruby -i`. Still allowed: reading, running tests (`python3 -m pytest`,
`node --test`), and writing inside the plan's files. A path held in a variable
cannot be read, so this stays a guard rail (see the first paragraph). Outside a
run, programs are not judged.

**Another session's run** (D11): while a run with an owning session is open
(under 24 hours), a call from a different session (`session_id` differs from
`lease.session`), main conversation or agent, is denied when it writes a file in
`lease.files` (any project file when `files` is null, none when `[]`): file
tools, shell redirects, `tee`, `cp`/`mv` onto it, `sed -i`, `rm`. The message
names the owning session; the user lifts it with `vbw run end --owner-closed`.
Other files stay editable, and the owning session is unaffected. A planning run
holds back only `.vbw/`, so it never blocks another session's source or docs
folders.

A lease older than 24 hours holds no one. During a run the Bash fast path is off
for subagents: every command they run is read.

## What each answer means

A hook gives Claude Code one of these answers. `tests/hook-answers.bats` pins
each one to the exact JSON.

| Answer | Sent by | What Claude Code does |
|---|---|---|
| `deny`, reason starting `VBW guard:` | the Bash and file guards | Blocks the tool call and shows Claude the reason, so it can choose another way |
| `ask`, with a rewritten question (`updatedInput`) | the approval-menu hook on `AskUserQuestion` | Shows the rewritten question to you; you answer it |
| Added context (`additionalContext`) | SessionStart; the approval-answer hook | Adds the text for Claude to read |
| A message for the user (`systemMessage`) | SessionStart (project made by a newer VBW, or VBW 2 just removed old VBW 1 command copies and you must reload); the approval-answer hook | Shows you the message |
| No answer (no output, exit 0) | every hook, when it has nothing to say | Goes on as it normally would: your permission settings and prompts decide |

### No hook ever answers allow

Claude Code reads `allow` as "the hook decided, do not ask the user". On a
question that would mean the hook answered it in your place, so the approval
hook answers `ask` instead. Only your exact answer `Approve` approves a
contract. A standards test (`tools/check-hook-answers.sh`) fails if any hook
could answer `allow`.

### A failing hook gives no answer, except during a run

Outside a run, the four guard and approval hook commands exit 0 with no
output when they fail (bad input, missing `jq`). During a run the two guards
(Bash and file tools) block instead, as described in "When a guard fails". The
session-start hook has no `|| true`: if it fails (for example, no `jq`), it
prints an error and exits non-zero, but it never prints a decision. When a
hook gives no answer, Claude Code goes on as it normally would. A failure never
becomes an `allow`; it becomes a `deny` only for a guard during a run. A corrupt
`.vbw/record.json` is not a hook failure: the folder still counts as a VBW
project, the guards stay on, and a guarded call such as `vbw approve` is still
denied with a `VBW guard:` reason.

## How a command is read

The Bash guard judges what the shell would execute, not the text:

- Each simple command is found by splitting on `;`, `&&`, `||`, `|`, `&`,
  newlines, parentheses, braces and backticks. Its program is the first word
  after variable assignments and wrappers (`sudo`, `env`, `command`, `exec`,
  `nohup`, `time`, `nice`, `timeout`, `xargs`, `rtk` (RTK's rewrites), `if`/`then`/`do`/...).
- Quoted strings and heredoc bodies are data: `git commit -m "never rm -rf /"`
  is allowed (ledger D281).
- What the shell runs from inside strings is judged too: `$(...)` and `` `...` ``
  inside double quotes, and the script given to `sh -c`/`bash -c` or `eval`
  (three levels deep).
- Only a real substitution counts. In `echo "run vbw approve"`, a commit message
  that mentions `` `vbw approve` ``, or `echo "typed: \$(vbw approve)"` (escaped),
  nothing runs, so nothing is refused. `echo "$(vbw approve)"` runs it and is
  refused.
- Redirect targets (`> file`, `2>> file`, `< file`) are paths like arguments.

Reading the plan of record is not writing it: `cat`, `jq`, `sort`, `awk`
(without in-place editing), and `cp`, `rsync`, `install` or `ln` with the record
as the source are allowed. A copier whose destination is the record, or any
other program that names it, is refused.

A command that contains none of the words any rule needs (`rm`, `git`, `vbw`,
`consent`, `record.json`, a secret file name) is allowed without being read.

## Engineering

- **Per-tool-call hooks are jq itself** (build plan K20): no shell script, no
  interpreter startup of our own. On a Mac, Homebrew bash takes 9 ms just to
  start; jq is required by VBW anyway.
- **The guard command's own shell tests pick the input; jq does the rest.** The
  tests are built into the shell (no other program): they pick the glance, or
  nothing when it is not current. jq then reads the hook input, the record only
  when needed, and a sentinel file. jq skips a missing file, so the sentinel
  says whether this is a VBW project.
- **A guard blocks by accident never, by failure only during a run.** The
  approval-menu command ends in `|| true`. The two guards exit 2 only when
  their run-open flag is set; otherwise a guard that errors prints nothing and
  Claude Code decides as it normally would. `tests/guard-fail-closed.bats`
  pins both.
- **Budget:** VBW's own cost (the hook's CPU time minus that of the platform's
  `sh -c jq` startup) is at most 20 ms per call, judged for each guard alone,
  measured by `tools/bench-hooks.sh` before every test run, including on a
  20 KB heredoc command. CPU time, so waiting for a busy machine never counts.
  On an idle Mac: file tools about 2 ms, Bash about 5 to 7 ms. A real slowdown
  (an added subprocess costs several ms) still shows. When the machine is too
  busy to measure (starting the shell and jq alone takes longer than 20 ms),
  the benchmark reports that the machine is busy, judges nothing and does not
  fail. CI runs it with the same limit as a local run.

## SessionStart

In a VBW project, one line of context: the project state and `vbw next`.
Started in a subdirectory of a VBW project, it says the guards are off and
where to start instead. It never writes and never injects resume directives
(ledger D289).
