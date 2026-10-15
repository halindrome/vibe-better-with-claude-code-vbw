# Contract and proof

VBW does not ask anyone to trust that work is done: it proves it. The user
states requirements in `.vbw/spec.md`; the plan workflow proposes checks; the
user approves the contract; `vbw prove` runs exactly what was approved and
records the evidence.

## The spec: `.vbw/spec.md`

The user owns this file. Free prose everywhere, except the `## Requirements`
section, where every bullet is a requirement:

```markdown
## Requirements

- R1 [auto] A visitor can sign up with an email address
  Notes for the Architect and Lead may follow on indented lines.
- R2 [human] The landing page feels trustworthy
```

- `R<n>`: a stable id, never reused. `vbw spec add` appends the next free one.
- `[auto]`: a check can prove it. `[human]`: only a person can judge it.
- Indented lines under a bullet are notes for the Architect and Lead; the kernel ignores
  them. HTML comments are ignored.
- Any other bullet in the section is an error, reported with its line number.

`vbw spec check` validates the file. `vbw spec sync` validates it and brings
the record in line: new ids are added as `open` to the current milestone,
changed text or proof resets the requirement to `open` (in the current
milestone), and an id removed from the spec is removed from the record with its
checks, its fix items, and the unstarted plans that served only it. Removing a
requirement whose only plans have already started is refused: built work is
never discarded without the user deciding.

The spec keeps every milestone's requirements. After a milestone ships, its
requirements stay (their checks keep running in every proof, guarding the
shipped work), and `vbw milestone start TITLE` opens the next milestone for new
requirements. The kernel never rewrites the spec; `vbw spec add auto|human
TEXT` only appends a line.

### Saved test results: `## Test results`

Some projects commit the output of their test runs (reports, recordings,
snapshots). List the folders that hold them under `## Test results`, one
folder per line. A folder name cannot contain spaces: `vbw spec sync`
refuses such a line and prints its line number.

```markdown
## Test results

- results/
- reports/benchmarks/
```

- Each line is `- <folder>/`: a path relative to the project root, with no `.`
  or `..` parts, outside `.vbw/`. A missing trailing `/` is added. A folder
  named twice, or any other bullet in the section, is an error with its line
  number. Text that is not a bullet is ignored, as in `## Requirements`.
- `vbw spec sync` copies the list into the record (`project.results`,
  docs/record.md) and prints the new list. It is part of the contract: adding,
  changing or removing the list needs approval like any other spec change, and
  `vbw show contract` shows the folders and how they changed. The list is
  compared with the record at approval like the other spec sections (see
  [The contract and approval](#the-contract-and-approval)).
- A file committed inside one of these folders is a saved test result. It does
  not make QA check a passed phase again
  ([Which phases QA checks again](#which-phases-qa-checks-again)).
- No section, no exemption: when the spec names no folder, a saved result is a
  file like any other.

## Checks

A check proves one `auto` requirement. It lives in the record:

```json
{ "id": "C1", "req": "R1", "run": ["npm", "test", "--", "tests/signup.test.js"],
  "files": ["tests/signup.test.js"], "exit": 0, "output": "1 passed", "timeout": 120 }
```

| Field | Rules |
|---|---|
| `run` | argv, a non-empty array of non-empty strings. Executed directly, never through a shell |
| `files` | optional: the test files the check depends on (relative paths, no `..`). Their contents are part of the contract, so editing them after approval is tampering |
| `exit` | optional expected exit status, default `0` |
| `output` | optional extended regular expression that stdout+stderr must match |
| `timeout` | optional seconds, 1 to 3600, default 300 |
| `alone` | optional boolean, default `false`. `true` marks a check that must not run beside any other VBW check (for example one that starts containers or binds a fixed port) |

`vbw prove` runs checks from the root of a clean copy of the committed code,
`vbw check` from the project root; both close stdin. A run that reaches its
timeout is stopped (by `timeout` where available, otherwise by `perl`'s alarm)
and fails. Every check and project command runs without `VBW_SESSION_ID`, the
session that is proving: a project's tests give one result whoever proves them,
and the figures a test records under a session id are its own, never the
prover's (docs/costs.md).

### Checks run in parallel

```text
vbw config set check_jobs 8     # up to 8 checks at the same time
vbw config set check_jobs 1     # one after another
vbw config set check_jobs default
```

`vbw prove`, `vbw check` and the checks of `vbw fix done` run at most
`check_jobs` checks at a time: 1 to 64. Without a setting, `check_jobs` is
three quarters of the processor cores, rounded down, at least 1 and at most 64
(a machine with 8 cores runs 6). It is 1 when the core count cannot be read.
`vbw config` shows the value and whether it is the machine default or set;
`vbw config set check_jobs default` returns to the default. The setting
belongs to this clone and is shared by its worktrees; it is not in the record
or the contract, so changing it needs no approval.

The limit is shared. Several VBW commands can run checks at the same time in
one project folder (parallel Devs each running `vbw check`, the round's one `vbw fix done`
beside `vbw prove`). Together they never run more checks than the limit. A
check that finds no free slot waits for one instead of failing, and its
timeout counts from its real start. A slot held by a VBW process that died is
freed. Checks that run alone are unchanged.

The results are the same as running the checks one after another: the
evidence lists them in the checks' own order, whatever order they finish in.
Checks marked `alone` (below) still run by themselves. A proof of many checks
takes about as long as its slowest checks, not the sum of all of them. Checks
that share a resource and are not marked `alone` (a database, a fixed port) can
disturb each other: mark them `alone`, or set `check_jobs` to 1.

### The computer-wide limit

VBW as a whole never runs more than the machine limit at once: three quarters
of the processor cores, rounded down, at least 1 and at most 64.
Every VBW project on this computer shares it, however many projects, sessions and runs
prove at the same time. It is not a setting. `check_jobs` stays as a per-run
cap below it; a run never goes above either number. `vbw config` prints a
`machine limit:` line with the number and says when it applies instead of
`check_jobs`.

Each check, each project command and each test file takes one slot while it
runs. The slots live in `<claude-config-dir>/vbw/slots.json`, where
`<claude-config-dir>` is `CLAUDE_CONFIG_DIR` if set, else `~/.config/claude-code`
if that folder exists, else `~/.claude`. The file exists only while runs use it.

Runs take equal turns: when slots free up, the waiting run holding the fewest
goes first; between equals, the one that waited longest. A run that waits
prints `waited ... for other VBW runs on this computer`. Waiting changes
nothing else: the same result as without it, and a timeout counts from when its command really starts.

If a run is killed, the next run takes over its slots. Ctrl-C gives them back
at once. A lock left by a dead process is taken over too.

If the store cannot be written (a read-only folder, the Claude Code sandbox)
or is damaged, the run goes on under `check_jobs` alone and prints
`the computer-wide limit was not in force` with the reason (at the start, or
once at the end when the store failed in the middle of the run). A store lock
held by a live process is waited for, however long.

### Checks that run alone

```json
{ "id": "C2", "req": "R1", "run": ["docker", "compose", "run", "--rm", "e2e"], "alone": true }
```

A check with `"alone": true` never runs at the same time as another VBW check
in the same project, even when several fixes or builds run checks in parallel.
Other checks keep running in parallel with each other.

Every running check registers in `.vbw/runtime/gate`. An alone check starts
when nothing else is running. A shared check starts when no alone check is
running or waiting, so a waiting alone check is not starved. The registration
is released when the check ends, times out or is interrupted, and a
registration left by a dead process is taken over.

A check that cannot start waits as long as the check holding the gate is alive,
and takes over when that check's process is gone. There is no wait limit
(`VBW_CHECK_WAIT_SECONDS` no longer exists), and the wait is not part of the
check's `timeout`, which counts only the run. A check whose runner ends without
leaving a result is recorded as `skipped` (its tail starts `not run:` with the
reason) and counts as not passed; every other result stands.

## The contract and approval

The contract is the requirements (id, text, proof, and rules when listed), the checks, the plans
(everything but their status) and the contents of every check's `files`. Its
hash is SHA-256 over a canonical rendering of all of it.

`vbw approve`, and `vbw next` before it offers the approval question, first
compares every section of `.vbw/spec.md` with the record:
Requirements, Commands, Test files and Test results. A spec that was edited and
not synced cannot be approved; the refusal reads
`spec.md and the record differ (vbw spec sync)`.
Run `vbw spec sync`, then approve.

### Approving by choice

When the contract is ready, VBW shows it and asks a question in Claude Code's
own question box. `vbw show contract` prints the question and its options:

```text
approval question: Approve contract 4cfe6f0859c9?
approval options: Approve, Not yet
```

- **Approve** comes first, so pressing Enter approves the contract shown.
- **Not yet** approves nothing; VBW asks what to change.
- **Your own words** (the box's own-answer slot) approve nothing either. VBW
  takes them as what to change, or as a question.

The 12 characters in the question are the contract's fingerprint (the start of
its hash). Approval covers exactly that contract. The question may carry more
text after the fingerprint (a sentence, spaces or line breaks that Claude adds
to explain what you approve). Choosing **Approve** still approves the contract
the fingerprint names; the extra text changes nothing. The fingerprint must
stay at the start of the question: a question that does not begin with
`Approve contract <12 characters>?` is not the approval question, and nothing
is approved. So that a reworded question still works, VBW adds the start
itself: when Claude asks a question with the options Approve and Not yet without
the fingerprint while a contract waits for approval, VBW puts
`Approve contract <12 characters>?` in front of it before you see it (the
`PreToolUse` hook `hooks/approve-ask.jq` and `hooks/approve-ask.sh`), so
Approve approves exactly the contract shown.

If the fingerprint is not the current contract's, nothing is approved. This
happens when the contract changed after the question was asked (a plan or check
was edited meanwhile), or when the fingerprint is wrong. VBW says
`the contract changed since you were asked (now ...): review it again`. Review
it with `vbw show contract` and answer the new question.

After any change to the plan (a new plan, a changed plan or a re-plan), VBW
asks for approval only with this menu. It never tells you to type
`/vbw:approve`. Typing `/vbw:approve` still works and approves the current
contract, without the question.

`vbw approve` (the user's answer or `/vbw:approve`, never the model) refuses an incomplete
contract (no requirements, an `auto` requirement without a check, a missing
check file), then records consent for the contract hash and for every project
command in `record.commands`, in the clone's git directory (see
docs/record.md, Consent), and logs a decision. A repository cannot ship
approval: a fresh clone must approve before anything runs. The kernel accepts
`vbw approve --hash FINGERPRINT` only when the fingerprint is the current
contract's.

### Test files edited while building

Devs often adjust a test file while building a phase. VBW asks about those
edits once, before the phase is proved, not once per edit.

Each approval remembers the contract's structure (requirements, rules, checks,
plans) next to the full hash. While only the bytes of check files differ from
what was approved:

- `vbw next` keeps building. `vbw check` runs, and prints
  `vbw: waiting for approval (changed since approved): tests/pay.sh` on stderr.
- When a phase is built and not yet proved, `vbw next` returns `approve` with
  `detail.files`: every edited test file, sorted. Review them with
  `vbw show contract --changes`, then approve once.
- `vbw prove` refuses and names the files: `check files changed since it was
  approved are waiting for approval: tests/pay.sh: review them, then /vbw:approve`.
  Nothing is proved.

A change to the structure (a new check, a changed `run`, a plan's files) is not
waiting: the contract needs approval first, as before.

### A regression test added by a QA fix

When QA finds a problem, the fix can add a test that would have caught it. The
Dev writes the test file, then registers it:

```
echo '{"run": ["sh", "tests/pay-zero.sh"], "files": ["tests/pay-zero.sh"]}' | vbw fix check F3
```

The document takes the same fields as a check in `vbw apply` (`run` and `files`
are required). The new check belongs to the finding's requirement, and
`vbw show req R1` names the fix it came from. Only a fix that QA opened can do
this; a fix for a failed proof is fixed in the code its check already tests.

The test is new, so nothing runs it until you approve it. The fix closes with
the checks already approved. When the fix is done, `vbw next` returns `approve`
once, naming every new or changed check file of the fix (`detail.files`):

```
approval question: Approve contract 4cfe6f0859c9?
approval options: Approve, Not yet
```

- **Approve** lets `vbw prove` run the new test with the others.
- **Not yet** approves nothing. `vbw prove` runs none of the waiting files,
  names them and says to approve; the fix stays open until you do.

The approval is by content: if the test changes again, it waits for a new
approval. See docs/guards.md for what the fix run may write.

### An approval whose commit fails

`vbw approve` commits the approval record. When that commit fails (a project
hook refuses it, or git has no identity), VBW stops and prints git's own reason
and `the approval commit failed (reason above); the contract is not approved`.
It exits non-zero and leaves no approval: the decision is not in the record and
no consent is kept. `vbw show contract` still says `NOT APPROVED` and `vbw next`
asks again. Fix the cause (for example, make the hook pass) and approve again.
Other VBW commits still only warn, with git's reason.

A project command or the test-file form changed after the contract was
approved is approved on its own, the same way: `vbw approve` records the
decision `Project commands approved: name (argv); ...` and its commit
`chore(vbw): approve commands` before it grants the consent, so the record and
git say what was approved and when. When that commit fails, the decision is
taken back, no consent is kept and the message ends `the commands are not
approved`. A loop records the same decision with its own words (docs/loop.md).

## Rules

A rule is one condition, edge or error case that an `auto` requirement's text
states, paired with the check that tests it. The Lead lists them with
`vbw apply` (docs/workflows.md), so an approved contract shows what each check
is meant to cover, not only that checks exist.

`vbw show contract` is the approval screen. Each `auto` requirement shows its
rules with their checks:

```text
R1 [auto] A customer can pay once
  rule: A payment succeeds -> C1
  rule: Paying twice is refused -> C2
```

- `vbw approve` refuses an `auto` requirement whose rules are pending
  (`rules: []`): `R1 has no rules listed (vbw apply with rules)`.
- Rules are part of the contract hash: adding, removing or re-pointing a rule
  needs re-approval, and `vbw show contract --changes` lists it as
  `added rule`, `removed rule` or `changed rule`.
- When a requirement's text or proof changes, `vbw spec sync` resets its rules
  to pending, so the Lead restates them.
- A requirement approved before rules existed (no requirement has a `rules`
  field) keeps its approval. Its screen shows `rules not listed`, and nothing
  forces rules until the Lead applies a plan that lists them (D53). Once any
  requirement has rules, new and changed `auto` requirements need them too.

## Project commands

The project's own test, lint and build commands live in `.vbw/spec.md`, under
`## Commands`, one per line: a name, then the command as words, or as a JSON
array when an argument contains spaces:

```markdown
## Commands

- test: cargo test --locked --workspace --manifest-path market_recorder/Cargo.toml
- pytest: conda run -n portfolium python -m pytest -q market_recorder/
- e2e: ["sh", "run tests.sh", "--fast"]
```

`vbw init` writes the commands it detects there as a suggestion (in a
repository with several sub-projects it sees only the root, so check them).
Edit a line to change a command, delete it to stop running it, then
`vbw spec sync`: the record's commands become exactly that section. A spec
without the section keeps the commands it has. A command whose exact argv the
user has not approved makes `vbw next` ask for approval again, and
`vbw prove` runs only approved commands.

### The time limit of project commands

A project command (the test run above all) runs for up to 3600 seconds
(60 minutes) under `vbw prove`. A project sets its own limit, from 1 to 86400
seconds, and returns to the default:

```
vbw config set command_timeout 7200
vbw config set command_timeout default
```

A command that reaches the limit is stopped and recorded with the status
`timeout`. The summary then names the limit it ran under and how to raise it:

```
  test stopped by its time limit (3600 s); raise it with vbw config set command_timeout SECONDS
```

A check's own `timeout` (1 to 3600 seconds, see [Checks](#checks)) is separate:
it limits that check only, and `command_timeout` does not change it.

### The quick command

A project whose test command is slow can name a faster variant for build and
fix rounds, with a `quick` entry:

```markdown
## Commands

- test: cargo test --locked --workspace
- quick: cargo test --locked --workspace --lib
```

The quick command needs approval like any other command: it is part of the
contract, and `vbw prove` never runs it before the user approves it. VBW never
detects a quick command and never suggests one (`vbw init` does not write one); only the
user can say which subset of the tests is enough for a build round.

A plain `vbw prove` runs the quick command in place of the test command. When
the quick command is not approved, the summary says so and the full test
command runs instead. `vbw prove --full` never runs the quick command. A proof
where the quick command stood in is partial: QA and shipping accept a proof that
reused results but refuse a partial one until a full proof ran. The refusals read
`the last proof was partial: run vbw prove --full, then record the verdict again`
(`vbw qa record`) and `Run vbw prove --full` (`vbw next`).

Any change to the contract (a check edited, a test file touched, a plan's files
widened) changes the hash, and the contract is unapproved again until the user
re-approves it. `vbw show contract` renders what is being approved, and
`vbw show contract --changes` only what changed since the last approval in this
clone (`vbw approve` keeps a copy of what it approved in `.vbw/runtime/`).

## Test files

A project whose test runner can run one test file at a time can say how, so a
change re-runs only the test files it can affect. The form is a `## Test files`
section in `.vbw/spec.md`, beside `## Commands`:

```markdown
## Test files

- run: bats {file}
- files: tests/*.bats
```

`run` is the command for one test file; it names `{file}` exactly once, and VBW
puts each test file's path there. `files` lists the git pathspecs of the test
files, one or more per line. The Lead proposes the form with the runner's
documented syntax (`vbw apply`, see docs/workflows.md). `vbw init` never writes
one: VBW never guesses a form.

The form is approved like a command. It is part of the contract, and
`vbw prove` never runs an edited form before the user approves it again. Without a
form (no section, or one not approved), the test command runs whole.

With an approved form, `vbw prove` runs each test file on its own, several at a
time, and reuses a test file's result like a check's (see
[Reusing results in `vbw prove`](#reusing-results-in-vbw-prove)). A test file
runs again when it is new or changed, when a file it read changed or was
deleted, when a folder it listed gained a file, or when its last result
failed. The summary counts them, as `test files: N ran, M reused`:

```
  test files: 3 ran, 41 reused
```

A failing test file fails the proof, and the proof names it. `vbw prove --full`
runs every test file on its own and reuses none.

A test file that an approved check runs runs only as that check, not a second
time as a test file. The quick command never stands in for an approved form:
with a form, neither the test command nor the quick command runs.

When that leaves no test file to run (every file the form matches is run by
an approved check), the test command counts as covered by those checks: it
passes with `test files: 0 ran, 0 reused`, and the summary says so. When the
form matches no committed file at all, the test command fails, the summary
names the pathspecs, and a fix opens for it: add the test files, or change the
form in `.vbw/spec.md`.

## `vbw prove`

1. Refuses unless the current contract hash is approved.
2. Makes a clean copy of the committed code (`HEAD`) inside the project, under
   `.vbw/runtime/`. The copy's folder is named after the process that made it
   (its owner, by process id), for example `.vbw/runtime/proof.48213.k3Xa9Q`.
3. Runs every check (up to `check_jobs` at a time, `alone` checks by themselves),
   and every project command whose argv is approved, from the
   root of that copy; an unapproved command is skipped and reported, never run.
   A check whose last pass is still valid for the files it read is reused, not
   run again ([Reusing results in `vbw prove`](#reusing-results-in-vbw-prove)).
   Then it removes the copy, also when interrupted.
4. Scope: every commit with a `VBW-Plan:` trailer naming a plan in the record
   must change only that plan's files.
5. Writes the evidence and updates requirements and fixes in one atomic record
   update, then prints a one-screen summary. Exit 0 only when everything passed.

### Timed speed checks are not part of the proof

`vbw prove` does not run VBW's own timed speed checks (the hook, status line
and panel benchmarks, and the test files named `tests/timed-*.bats`), so a busy
machine never fails or delays a proof. They run once per release, in
`bash tools/test.sh --release`: in CI and before a push. `bash tools/test.sh`
without `--release` runs the same lint and tests the proof runs, without them.

### Full and partial proofs: `vbw prove --full`

```text
usage: vbw prove [--full]
```

`vbw prove --full` runs everything fresh: every approved check and every
approved project command, and never the quick command. It reuses nothing. Any
other argument is refused with the usage line, and nothing runs.

A plain `vbw prove` may reuse results
([Reusing results](#reusing-results-in-vbw-prove)). A proof is full only when
all of these hold; otherwise it is partial:

- it reused no check or other command result,
- it ran the test command, and not the quick command, and
- every project command ran (none was skipped as not approved).

The release run of VBW itself (`bash tools/test.sh --release`) reuses a passing
proof whether or not it reused results: a reused result is one the read lists
still vouch for. It does not reuse a proof that skipped a command or let the
quick command stand in.

The summary ends with `proof: full` or `proof: partial`, and the evidence
records the same in its `full` field (docs/record.md).

QA and shipping accept a proof that reused results. `vbw qa record` and
`vbw ship` need a proof that covers the current contract and code and passed.
A reused result is taken only when nothing its check read has changed, so a
proof that reused passing results counts as much as one that ran them. They
refuse a proof that is out of date or failed:

- `vbw qa record` prints the reason and asks for `vbw prove` first;
- `vbw next` returns the `prove` step before QA or shipping when the last
  proof is out of date.

For every check run fresh, use `vbw prove --full` (see
[Limits](#limits-of-reusing-results)).

### Proof in the background during an autonomous run

In an autonomous run (`/vbw:vibe --auto`), a stop hook runs each time Claude
stops. It reads `vbw next` and, until a step needs you, tells Claude to do the
next step. A proof can run in the background while Claude stops. To keep the hook
from asking for the proof again, `vbw prove` writes a mark for its session,
`.vbw/runtime/proving.SESSION_ID`, holding its process id, and removes it
however the proof ends (also on an error or an interrupt).

While that mark names a live process, the hook asks for nothing and spends no
autonomous step (`settings.autonomy_cap`) on the proof. When the proof ends, its
result wakes the session and the run continues. A mark left by a dead process is
stale and ignored. The mark belongs to one session: another session's proof does
not pause this session's run.

Because the copy holds only committed files, uncommitted edits and untracked
files in the working folder change no result. A check file that is not
committed as approved is refused: commit it, then `/vbw:approve`.

Git-ignored files (`node_modules/`, `.venv/`, `.env.local`) are the project's
environment, not its code, so the copy holds them too. They are copied, not linked.
A linked folder would let a proof write into the working folder, and some
tools refuse a linked `node_modules` outright (pnpm 11 does). A copy behaves as
the working folder does, and nothing a proof does changes the working folder.
VBW makes a copy-on-write clone where the file system offers one (APFS on macOS,
btrfs or XFS on Linux), which is instant and takes no extra space. Where it does
not, VBW makes a plain copy, which is slower for a large folder.
Links that sit inside a copied folder stay links. When one is an absolute link
into the working folder, VBW prints a `vbw:` line naming it and still copies it
as it is. If an ignored file or folder cannot be read, the proof stops with an
error naming the path, instead of running on an incomplete copy.

Build output is not environment: the copy never brings in a folder named `target`,
`dist`, `build`, `bin`, `out`, `__pycache__`, `.pytest_cache`, `.mypy_cache`,
`.ruff_cache`, `.tox`, `.next`, `.nuxt`, `.gradle` or `coverage`, at any depth.
The copy builds its own, so a proof never reads stale output from the working
folder, and nothing it builds lands in the working folder or in another copy.
Untracked files that are not ignored never enter the copy (D54): to make one
count, commit it or ignore it.

#### Leftover proof copies

A proof killed outright can leave its copy behind. The next `vbw prove` or
`vbw fix done` removes every leftover copy whose owner (the process named in
the folder) has ended, together with its git worktree entry. It never removes a
copy whose owner still runs. A copy without an owner in its name (made by an
older VBW) goes once it is more than 24 hours old. A copy that cannot be
removed (a locked file) leaves the result unchanged and prints one line:
`vbw: cannot remove the leftover proof copy <path>; remove it by hand`.

#### Links left pointing into a proof copy

An earlier VBW linked git-ignored folders into its proof copies. A link like
that can survive in your working folder and break once the copy is deleted.
After every `vbw prove`, VBW scans the working folder for such links and prints
one line for each:

```text
vbw: node_modules/.bin/tsc -> /home/me/app/.vbw/runtime/proof.k3Xa9/node_modules/typescript/bin/tsc points into a proof copy of an earlier run; re-run the project install command
```

The line names the link, where it points, and the repair. It appears only when
such a link exists; with none, VBW prints nothing. The scan only reads: it
changes no file, never follows a link, skips `.git` and `.vbw`, and never turns
a passing proof into a failing one. It also runs when the proof stops early
with an error.

To repair, rebuild the folder that holds the link:

- **pnpm projects** (a `pnpm-lock.yaml` or `pnpm-workspace.yaml` exists): delete
  `node_modules`, then run `pnpm install`.
- **Other projects:** re-run the project's install command (`npm install`,
  `pip install -r requirements.txt`, `bundle install`, and so on). If a link
  remains, delete the folder it sits in and run the install command again.

The warning stops once no link points into `.vbw/runtime/proof.*`.

Evidence (`record.evidence`):

```json
{ "at": "2026-10-01T09:00:00Z", "contract": "<sha256>", "tree": "<git tree id>", "passed": false,
  "checks": { "C1": { "status": "fail", "exit": 1, "seconds": 3, "tail": "…" } },
  "commands": { "test": { "status": "pass", "exit": 0, "seconds": 9, "tail": "" },
                "lint": { "status": "skipped", "exit": null, "seconds": 0, "tail": "not approved" } },
  "scope": [] }
```

Statuses: `pass`, `fail`, `timeout`, `skipped`.

`tail` holds only the end of the output. When a check or project command fails
or times out, `vbw prove` keeps its full output in a file, so you can read the
whole failure without running everything again:

```text
.vbw/runtime/output/C1.log            check C1
.vbw/runtime/output/command-test.log  project command test
```

- There is one file per check or command, holding its latest failure; a newer
  failure replaces it.
- A pass removes the file.
- A reused result, or a check that was skipped, leaves the file as it is.
- `.vbw/runtime/` is git-ignored, so these files are never committed.

An `auto` requirement is `proven` when all its checks pass and `failing`
otherwise. Human requirements are untouched.

### Reusing results in `vbw prove`

Most commits after a passing proof touch only part of the code. `vbw prove`
runs again only the checks a change can affect, and reuses the passing result
of every other check.

```text
C1 pass 2s reused (proof of 2026-10-07T20:49:55Z)
C2 pass 3s
lint pass 9s reused (proof of 2026-10-07T20:49:55Z)
checks: 1 ran, 1 reused
```

Each line shows the seconds the result took when it ran and, for a reused
result, the time of the proof that really ran it. A reused result keeps the time
it really ran and the fingerprint of that run, so reuse can chain across proofs.
In the evidence, reused results carry `"reused": true`, and the summary counts
`checks: N ran, M reused` and `test files: N ran, M reused`.

**The read list.** While a check runs, VBW records its read list: the files it
opened and the folders it listed. The list comes from the run itself,
never from file names, and not from the `files` a check declares. A check that
declares no files is judged by what it read, like any other, and a documentation
file a check reads is on its read list like any other file.

**When a result is reused.** A check's last pass is reused when the check has a
read list and nothing on it has changed since that pass.

**When a check runs again.** Every reason:

- Its approved definition changed (its command, expected exit and output,
  timeout, `alone`, `files` or requirement).
- A file on its read list was changed, deleted or renamed.
- A file or a sub-folder was added to or removed from a folder on its read list
  (a sub-folder appears with its first file and vanishes with its last).
- Its last result failed (fail, timeout or lost).
- It never passed: it is new, or no earlier proof ran it.
- It has no read list (for example, the earlier run recorded none).

A check removed from the contract is left out of the new proof.

**Where read lists are kept.** In `vbw/runs.json` in the clone's git directory
(`git rev-parse --git-common-dir`), never in the record. A lost or damaged
file only makes the checks run again. The store is protected
(docs/guards.md).

**Speed.** Checks still run several at a time (`check_jobs`), each in its own
clean copy of the committed code.

Other things to know:

- An uncommitted change in the working folder does not make a check run again,
  and is never counted as proven: the proof reads only the committed code.
  Commit the work, then run `vbw prove`.
- An interrupted proof recorded no evidence, so the next proof runs every check.
- Project commands and test files follow the same rule. `vbw prove` reuses the test command's
  passing result when nothing it read changed; a command runs again only when its
  approved argv or time limit changed, a file it read changed, or its last result
  did not pass. A changed approved command re-runs only that command; a changed
  single-file form re-runs every test file; a changed list of test files runs the
  files it adds. Each unit re-runs by its own definition and its own read list, so
  none of these runs everything.

A proof that reuses results records the current contract and code. `passed` is
set from every result, reused or new, and requirements become `proven` as
usual.

#### When a proof runs everything

When VBW cannot tell what a change affects, it does not guess: every check and
test file runs, and the summary says why. One cause prints on one line; several
print as a list.

```text
  ran everything: this clone has no earlier recorded run
```

```text
  ran everything, because:
    - this clone has no earlier recorded run
    - this file system does not record which files are read
```

The causes, with the text the summary shows:

| What happened | Message |
|---|---|
| A file was added that no recorded run read and no recorded run listed its folder | `src/new.txt was added, and no recorded run read it or listed its folder` |
| A file was deleted under the same condition | `src/old.txt was deleted, and no recorded run read it or listed its folder` |
| The file system cannot record which files are read | `this file system does not record which files are read` |
| The clone has no earlier recorded run | `this clone has no earlier recorded run` |
| The last proof was cut short | `the last proof was cut short` |
| `vbw prove --full` | `vbw prove --full` |
| Nothing was committed since the last passing proof (`vbw prove` only; `vbw fix done` reuses that proof): the project's files are the tree the last passing proof recorded (`evidence.tree`), the committed code is the tree it ran on (`evidence.head`), the record is as that proof left it (its fingerprint without the evidence is `evidence.record`: a decision, a verdict or a backlog item recorded since is a change, and the proof reuses by read lists), and the record's last proof passed | `nothing was committed since the last passing proof` |

A content change to a file no recorded run read runs nothing: it affects
nothing that was run. An added or deleted file no recorded run saw (none read
it or listed its folder, and every recorded run predates it) runs everything,
because a check could now see a different set of files. An addition or deletion
that some recorded run already ran with is not unseen: the proof that ran it
judged it. A file whose own folder appeared or vanished with it (the first file
of a new sub-folder, the last file of one) is seen through the nearest folder
above it that a recorded run listed: that listing gained or lost an entry, so
the run that listed it runs again and nothing else does. A changed approved command, single-file form or list of test files
is no cause either: each unit re-runs by its own definition
([Reusing results](#reusing-results-in-vbw-prove)).

Every summary, full or not, prints both counts:

```text
  checks: 1 ran, 1 reused
  test files: 2 ran, 40 reused
```

They read `checks: N ran, M reused` and `test files: N ran, M reused`. After
`vbw prove --full`, the reused counts are 0.

#### Limits of reusing results

- What lies outside the project is not tracked: installed tools, the network
  and the clock. A check that depends on them can pass from reuse after they
  changed.
- A check that only looks whether a file exists, or at its size, without
  opening it, does not put that file on its read list.
- Reads through git always run again. Any git command whose working directory
  is inside the project counts, even one that reads nothing of the project
  (`git config --global` run from the project folder): git opens the
  repository before it does anything else. A test suite that runs such
  commands from another folder keeps its results reusable.

To run everything fresh, use `vbw prove --full`, or prove again with
nothing committed since a passing proof (a second `vbw prove` is a deliberate re-run).
That last cause is `vbw prove`'s alone: `vbw fix done` right after a passing proof
reuses what the rule allows, because a passing proof of the same code is exactly
what it needs. VBW compares those trees and the record's fingerprint, and
never the subject of the last commit, so a VBW record commit landing after code
commits re-runs nothing it need not. Those are the cause's only conditions: the
contract and the commands live in the record, so its fingerprint covers them.

### Fix items

A failure becomes a fix item: `req` for a failing requirement, `command` for a
failing project command. Lifecycle:

| Before prove | Target passes | Target fails |
|---|---|---|
| no fix item | nothing | new fix, `open`, `attempts` 0, once the work is built (below) |
| `open` (no work yet) | `closed` | stays `open` |
| `fixed` (work committed and verified by `vbw fix done`) | `closed` | `attempts` + 1, back to `open`; `escalated` at the cap (3) |

A failure opens a fix only once the work is built: every plan serving the
requirement (for a project command: every plan) is `done`. Before that, a
failing check is work in progress, not a defect, and opens nothing.

`vbw fix done` is verified, not claimed: none of the files the fix may touch has
uncommitted changes, and the checks of every finished requirement (all its plans
`done`) that those files serve pass now. A fix cannot quietly break other work.
A project command's fix is left to `vbw prove`, which runs the command. A fix of
the test command with a single-file form is the exception: it judges every test
file by the reuse rule (the failed file and any changed file run, the rest are
reused and counted), and saves the files it ran for the next proof to reuse.

`vbw show fix F1` names each failing check's or project command's kept full output
file (`full output: .vbw/runtime/output/C1.log`), listed under it. When no file is
kept, for example after it was removed, it says
`full output not kept: run vbw prove again`. With `--json`, each failing check
and command has a `kept` field: the file's path, or `null`.

### Closing several fixes

```text
vbw fix done F8 F9 F5
```

One command closes several fixes. The checks that their files serve run once
(the union, not once per fix), and a check that passed earlier is reused as
below. Each fix ends as it would if closed alone: `fixed` and awaiting
`vbw prove`, or, for a `[human]` requirement, `closed` with the requirement
back to the user for acceptance. Naming an id twice closes it once.

A fix of the test command with a single-file form judges every test file by the
same rule: the failed file and any changed file run, the rest are reused and
counted. The files it runs are saved for the next proof to reuse.

A fix that cannot close is named, and the others still close. The cases:

- an unknown id, or a fix that is not `open`;
- uncommitted changes in a file the fix may touch;
- a failing check: only the fixes whose requirement that check serves fail
  (`F2 broke finished work`, with the check), the rest close.

The exit code is 0 when every fix closed and non-zero when any could not. A fix
that could not close keeps its status and `attempts`; fix the cause and run
`vbw fix done` again for it.

### Reusing an unchanged pass

`vbw fix done` follows the same rule as `vbw prove`
([Reusing results](#reusing-results-in-vbw-prove)): a check whose last pass is
still valid for its read list is not run again. It prints one line per check
and per test file, reused or run, and then both counts:

```text
C1 pass 2s ran: src/pay.txt changed
C2 unchanged since its pass (2026-10-04T20:30:00Z)
tests/t_a.sh pass 3s ran: last result failed
tests/t_b.sh unchanged since its pass (2026-10-04T20:30:00Z)
checks: 1 ran, 1 reused
test files: 1 ran, 1 reused
```

Each check and test file that ran gets a line in the proof summary's wording,
with the reason it ran; a reused one keeps the time of the pass it reuses.
Both count lines print after every per-unit line, every time (`0 ran, 0
reused` when nothing was judged), before the closing outcome lines. A check
runs again for any reason listed there: a changed approved definition, a
changed file on its read list, a last result that failed, no earlier pass or
no read list. When a cause ([Causes](#causes)) makes the rule run every
candidate, the cause line comes first and every unit ran, with no reason of
its own:

```text
every candidate check runs: this clone has no earlier recorded run
C1 pass 2s
C2 pass 1s
tests/t_a.sh pass 3s
checks: 2 ran, 0 reused
test files: 1 ran, 0 reused
```

An escalated fix is a human gate (`vbw next`).

Accepting a `[human]` requirement (`vbw req accept ID`) closes only the fixes
that the user's own rejections opened (`vbw req reject ID NOTE`). A fix that QA
opened (`source: "qa"`) stays open after acceptance and closes only on a passing
QA verdict (below).

### Skip for now: judging a `[human]` requirement later

When you cannot judge a `[human]` requirement yet, answer "Skip for now". The
skill records it with `vbw req skip R2`. The three answers stay: Works
(`vbw req accept`), Something's wrong (`vbw req reject`) and Skip for now.

If every other requirement is done and only skipped `[human]` ones remain,
`vbw next` offers `ship` and names them in `detail.later`. You choose once:
ship now and judge them in the next milestone, or judge them now (`vbw req
accept R2`). Looking at the offer changes nothing in the record.

`vbw ship` then ships the milestone. Its decision counts only the requirements
that were proven or accepted and names the moved ones
(`...; moved to the next milestone to judge: R2`). `vbw milestone start TITLE`
moves each into the new milestone with the same id, text, proof type, rules and
history (fixes, decisions, checks), status `open`. `vbw next` there asks you to
accept it. Its line in `.vbw/spec.md` stays as it was, and `vbw spec sync`
neither resets nor duplicates it.

What never moves: an `[auto]` requirement (`vbw req skip` refuses it; a check
can judge it), and a `[human]` requirement with an open fix from your rejection
(`vbw req skip` refuses it too). Finish the fix with `vbw next`, then judge the
requirement or skip it. `vbw ship` refuses while such a fix is open.

### The mutation check

At standard and deep, the builder breaks the plan's code on purpose (one
statement per rule) with `vbw mutate` and runs the rule's own check. See
docs/workflows.md for the command and docs/rigor.md for the levels.

A break with several checks (a task at deep) runs them one at a time, fastest
first by their last recorded time, and stops at the first that goes red; a
survivor runs them all. Each check first runs once on the unbroken code at that
commit, unless an earlier break at the same commit already ran it. A slow test
suite therefore pays for the checks a break needs, not for every check.

- A check that notices the break is **red**: the rule is covered.
- A test that cannot fail, because every check stays green, is a **survivor**.
  The Dev strengthens it in place, in the check file of that rule's own
  requirement (never another's, never weakened), then repeats the same break
  until it is red. After two attempts that stay green the Dev blocks the plan.
- `vbw plan done` waits for the breaks: at standard it refuses until each
  approved rule of the requirements the plan completes has a red break, and
  lists the rules missing one. A rule that names its plan (`plan` in the
  Lead's rules: the plan that builds its code) is asked of that plan when it
  finishes, even while another plan of the requirement is open, so each plan
  breaks its own rules. At deep each task also needs a red break or a
  written reason. At express it asks for nothing. A survivor alone covers
  nothing.

A strengthened check file adds one approval. The build finishes, then `vbw next`
asks you to approve the file before the proof, and `vbw prove` refuses until
you do. Under a loop, the loop gives that approval and records a decision that
names the file. A changed check file that no mutation check strengthened, or
one edited again after its red break, still waits for you.

### QA verification

Passing checks prove each requirement's behavior; they cannot see whether the
work matches the plan that was agreed. After a passing proof, VBW 1's QA agent
verifies each built phase goal-backward, at the profile's tier, against its goal
and criteria (the Architect's) and its plans' tasks (the Lead's): test gaps and
every deviation from the plan are failures. Each failure is recorded with
`vbw qa finding PHASE REQ TEXT` (the phase whose QA found it; a finding given
without the phase is adopted by that phase's fail verdict), a fix item with
`source: "qa"` that a proof never closes; the verdict with `vbw qa record PHASE
pass|fail TIER`, against the phase's inputs (see "Which phases QA checks
again"). A verdict changes only its own phase's findings: a pass closes them,
never another phase's, so phases that share a requirement can be verified in
parallel (D332); three failed rounds in a row escalate. A round after a fail
verifies that round's fixes, not the whole phase again
([Re-check rounds](#re-check-rounds)).

Only behaviour blocks (D400). A finding is code that does something wrong or
misses a promised behaviour, a test gap, a deviation, or a document stating a
false or missing fact the user relies on (a command, setting, number, file or
limit). Wording, tone, style, naming and a test that does not pin a sentence's
exact words are notes: QA lists them in its summary, and they never fail a
phase.

The project's test command is not run again for QA. The proof runs it once
(a project command, above) and `vbw next` hands that one result to the QA round
(`round.suite`, docs/next.md). QA agents use it as evidence and do not run the
suite themselves.

Every QA agent's prompt names the test command, its result (`pass`, `fail`,
`timeout`, `skipped` or `not run`), its exit code, its time and how its output
ended. A piece the round does not carry is named in plain words, for example
"its output was not kept"; the prompt never prints `undefined`. When the
command did not run, the agent is told not to retry it and to say in its
summary that the suite was not run. When the project has no test command, the
agent is told so and says so in its summary.

### Which phases QA checks again

After a round of fixes, QA checks only the phases that need it. An untouched
phase keeps its pass. A built phase is checked again when:

- it never passed, or its last verdict was a fail;
- its own inputs changed since it passed: its files (the files of its plans),
  its tests (its requirements' checks and their files), or its goal and plan;
- the tests of a phase it builds on changed (that phase's requirements' checks
  or their files), even if its own inputs did not. A phase builds on another
  when one of its plans comes after a plan of the other, directly or through
  other phases. A change to that phase's code, documents, saved results, goal
  or plan does not list it: that phase is checked again itself, and what the
  phases built on it rely on is what its checks promise;
- one of its `[auto]` requirements was added, reworded or removed.

Files and tests count as committed (`HEAD`), so commit work before QA.

Updating VBW alone never lists a passed phase. Each pass's fingerprint carries
the version of how it was computed. When an update changes that method, the
phase is compared as it was at its pass (at the commit the pass was recorded
at), computed the new way. Only a real change to its files, tests, plan or
requirements lists it, with the usual reason. If that commit is not in this
clone, the phase is checked again as described below.

These changes do not list a passed phase again, because QA has nothing new to
judge:

- a recorded decision (it is not code, a test, a goal or a requirement);
- a finding closed with no code change (the files are the same);
- a removed [human] requirement, or a reworded one (QA never judges what only
  a person can: `[human]` requirements are not among QA's inputs).
- a change to documentation only: files ending in `.md`, `.markdown` or `.rst`.
  A plain `.txt` file counts as data, so changing it lists the phase;
- a change only to saved test results inside the approved `## Test results`
  folders ([Saved test results](#saved-test-results--test-results)).

These exceptions have limits. The phase is still listed when:

- the file is one a check uses: a file in one of its checks' `files`, or named
  in a check's command. That file is a test, even as Markdown or inside a
  results folder;
- every plan of the phase changes only documents (a documentation-only
  phase): its documents are its code;
- the same change also touches code, tests, the goal or the plans;
- a results folder was added or removed but the new list is not approved yet.
  Until approval, a file in the new folder counts like any other file.

Changing the approved folder list checks once more each phase whose plans list
files inside the folders added or removed; the new pass stores the new list.

The rule works on each input separately. A skip-type change that comes together
with a listed change does not protect the phase: a decision plus a changed test,
a closed finding plus a code change, or a removed [human] requirement plus a
changed goal still list the phase, with the reason of the listed change.

Re-planning mid-milestone (`vbw apply` with phases added or changed) keeps each
existing phase's QA verdict. QA then checks again only the new phases and the
phases whose own inputs changed, by the rule above.

```
$ vbw show qa
P1 is checked again: its files changed
P2 is checked again: builds on P1, whose tests changed
P3 keeps its pass
```

`vbw show qa` prints one line per built phase: the phases checked again with
every reason (several reasons are joined with `; `), then the phases that keep
their pass. When no phase needs checking, the first line is
`Nothing needs checking again`. A line starting `problem:` names a plan link that
points nowhere or loops.

The reasons, in plain words:

| Reason | Meaning |
|---|---|
| `not checked yet` | QA has never recorded a verdict for the phase |
| `failed last time` | the last verdict was a fail |
| `its files changed` | a file of one of its plans changed since it passed |
| `its tests changed` | a check of its requirements, or a file of that check, changed |
| `its goal or plan changed` | the goal or the plans changed |
| `an [auto] requirement changed` | an `[auto]` requirement of the phase was added, reworded or removed |
| `builds on P1, whose tests changed` | a check of a phase it builds on, or a file of that check, changed |
| `its files, tests or plan changed` | something changed, but the cache that says what is missing |

`vbw next` sends only these phases to QA, gives the reasons in its `qa` key
(docs/next.md) and states them in its instruction line. The QA skill tells the
user the same. `vbw qa record PHASE pass` stores a digest of the phase's inputs
and the tests of the phases it builds on in the phase's `qa.tree` (docs/record.md).

#### Re-check rounds

The whole-phase sweep runs once, at a phase's first QA round. When the last
verdict was a fail and the phase's goal, criteria, plans and `[auto]`
requirements are unchanged since, the next round is a re-check round: `vbw
next` adds the phase to `round.focus` with `since` (the commit the failed
verdict was recorded at), `round` (2 or more) and `fixes` (the QA fixes of the
phase still open or fixed, each with its requirement and note). The QA agent is
told to verify only those fixes, the files changed since that commit and what
they reach, and that the goal still holds; anything else it notices is a note
unless it breaks the goal. A change to the goal, criteria, plans or `[auto]`
requirements since the failed verdict, or a clone without the cache
`qa.json`, brings back the whole-phase sweep.

A record from before this rule holds the proof's tree id in `qa.tree`. It matches
no digest, so each such phase is checked once more, and the new pass stores a
digest. The same happens when the clone's cache `qa.json` is missing or damaged:
the cache only names the reason, never decides, so a phase is checked again with
the reason "its files, tests or plan changed".

`vbw qa record` refuses a verdict when no proof exists yet, or when the project
files differ from the proof's `tree` (the code changed since the last proof). The
error asks for `vbw prove --full` first; the verdict is recorded only against a proof of
the current code. The QA agent handles the refusal itself: it runs
`vbw prove --full` and retries the record once.

### Freshness

Evidence carries two fingerprints. `tree` is a git tree id of the working
folder when the proof finished: tracked and new files, committed or not,
`.vbw/` and ignored files excluded. `head` is the tree of the committed code
the checks ran on, `.vbw/` excluded. `vbw next` treats evidence as stale, and
asks for `prove` again, when the contract changed or either fingerprint no
longer matches: the working files changed, or new code was committed (an edit
proved while uncommitted and committed later was never checked). Committing
VBW's own record changes nothing.

Uncommitted changes are not proved. Commit the work, then run `vbw prove`, so
the evidence covers the code you will keep.

### `vbw check [--expect-red] [CHECK...]`

Runs the given approved checks (all when none are given) on the working folder,
uncommitted and untracked files included, reports, and writes nothing: the
Dev's tool for the red and green steps. Exit 0 when all pass. With `--expect-red`, red-first:
before a plan is built its checks must fail, and a check that already passes
proves nothing, so exit 0 only when every check fails.
