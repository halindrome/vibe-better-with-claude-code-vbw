# Several sessions on one project

Two or more Claude Code sessions can work on the same project at once, for
example you in one window and a teammate's agent in another, or two windows of
your own. VBW keeps them from writing over each other while a run is open, and
tells each session what the other is doing. This page says how to set that up,
what VBW does when a second session meets a run in progress, and where two
sessions can still get in each other's way.

## Set up

- **Start each session at the project root** (the folder that holds `.vbw/`), or
  in a folder inside it. VBW finds the project from git: it uses the top folder of
  the repository, so every session in the repository sees the same
  `.vbw/record.json`. The Sessions tab lists the chats whose folder is the
  project or one inside it, and no others.
- **Give each session its own area.** One session builds the plans of one phase
  while another works on files that phase does not touch (documentation, another
  phase's plans, a bug fix). A build run holds back only the files of the plans it
  builds, so the other session can edit everything else.
- **Name each session with `/rename`.** The name is what the other sessions see
  when they are told who holds the run. VBW never renames a chat; when two chats
  are open on the project and yours still has the name Claude Code gave it, VBW
  suggests `/rename vbw · <project name>` once per clone
  ([`rename_hint`](next.md#the-rename-hint)).

## Who holds the run

A run (`plan`, `build`, `fix`, `qa` or `map`) is VBW's unit of work. While one is
open, the record holds its lease with the id of the session that started it
([workflows](workflows.md)). That session holds the run. Only one run is open at a
time in a project.

When another session asks VBW for the next step, or tries to start a run, it is
told:

```
A VBW build run (build-20261024T101500Z) belongs to another session, api-work: wait for it, or check vbw status
```

What to do:

1. **Wait.** This is the normal case. The run ends when its workflow finishes,
   and the next `/vbw:vibe` in the other session carries on from the new state.
2. **Work on something else meanwhile.** The guard refuses the other session's
   writes only to the files the run may write (a build run: the files of its
   plans; a planning run: `.vbw/` only; QA and map runs: none). Every other file
   stays editable ([guards](guards.md)).
3. **Ask the holder's session.** Its name is in the message. Only the session that
   holds a run can end it; `vbw run end` from another session is refused.
4. **If the holder is closed:** when you know that session is gone and the run
   will never finish, tell VBW so and it ends the run for you with
   `vbw run end --owner-closed`. A run older than 24 hours holds nobody and can
   be ended or replaced without that flag.

VBW ends a run it does not hold only on your word: Claude reports the refusal and
waits for you to say the holder is closed.

## Seeing who holds what

- **The status line** shows the run on its first line: `· leading` in the session
  that holds it, `· held by <name>` in any other session (the name is cut to 20
  characters; with no name known it shows the first 8 characters of the session
  id) ([statusline](statusline.md)).
- **The Sessions tab** of Mission Control lists every chat on the project, newest
  first. The holder's row says `● holds the run` with the run's kind, your own row
  says `this chat`, and each row has `claude --resume <session id>` ready to copy
  ([panel](panel.md#sessions)). A holder that is no longer in Claude Code's list
  is still shown, as `closed or not seen`.
- **`vbw next`** names the holder in its answer, as in the message above.

The holder's name is read from Claude Code's own list of chats and kept on your
computer only (`.vbw/runtime/holder.json`). It is never written to the record or
to git ([workflows](workflows.md)).

## What is shared and what is per session

| Shared through git and the project folder | Per session or per computer |
|---|---|
| `.vbw/record.json`: the plan of record, checks, decisions, costs and the run lease | `.vbw/runtime/`: locks, caches, the holder's name, the cost figures of each session (`cost.<session>.json`) and each session's autonomous-run state (`auto.<session>.json`). It is ignored by git |
| `.vbw/spec.md`, the working tree and its commits | Claude Code's own list of chats, which VBW only reads |
| The files of your project | The settings of this clone (`rename_hint`, `check_jobs`), kept in the clone's git directory |

Because both sessions use one working tree, they also share HEAD, the index and
any uncommitted change. Every write VBW makes to the record goes through one lock,
so two sessions never corrupt it. VBW commits only its own files, by explicit
path, and leaves the files you staged staged.

Two sessions in two separate checkouts of the repository (for example two git
worktrees) do not share a working tree. Each has its own `.vbw/record.json` and
`.vbw/runtime/`, so each can hold a run at the same time; they meet through git,
as any two branches do.

## Pitfalls

- **Two sessions planning the same milestone.** A planning run holds `.vbw/` while
  it is open, so the second session is told to wait. Outside a run nothing holds
  the spec: both sessions write the same `.vbw/spec.md`, as with any shared file,
  and a changed contract needs your approval again. Decide which session owns planning and let the other build or review.
- **One session's approval answering another's question.** The approval question
  carries the contract's fingerprint, and an answer approves exactly that
  contract. If another session changes the contract after you were asked, your
  Approve is refused with `the contract changed since you were asked`, and nothing
  is approved. Read the new contract and approve it. VBW never approves a
  contract you have not been shown.
- **Ending a run you do not hold.** The refusal is deliberate. Use
  `--owner-closed` only when you know the holder is gone; the holder's agents may
  still be writing if it is not.
- **Shared git state.** A branch switch, a `git stash` or a `git reset` in one
  session moves the files under the other. VBW's guards forbid these to a run's
  agents; they cannot forbid them to you. Agree on one branch for the project, or
  use separate checkouts.

## The loop is one session's

`/vbw:loop` ([loop](loop.md)) works through backlog items while you are away. It
belongs to the session that started it: only that session's Stop hook drives the
loop's steps, and any other session ignores it. Any session of the project can
read the loop's state (`vbw loop status`) or stop it (`/vbw:loop stop`). While the
loop's run is open, other sessions meet the same "belongs to another session"
answer as for any run. VBW refuses to start a second loop while one is on.

<!-- sources:
plugin/lib/cmd-run.sh: lease holder, 24 hour limit, refusals of run start and run end, --owner-closed, holder.json written at start and cleared at end
plugin/lib/sessions.sh: list of chats read-only, holder_display order, sessions_project_entries (folder or inside it), rename hint (once per clone)
plugin/lib/next.jq: "belongs to another session" answer of vbw next
plugin/lib/core.sh: vbw_project uses the git top folder, vbw_session, VBW_RUNTIME
plugin/lib/cmd-init.sh: runtime/ ignored in .vbw/.gitignore
plugin/lib/record.sh: record lock, record_commit by explicit path with git commit --only
plugin/lib/cmd-approve.sh: "the contract changed since you were asked"
plugin/hooks/approve-ask.sh: the fingerprint put in front of the approval question
plugin/hooks/common.jq: foreign (another session) lease, 24 hours
plugin/hooks/guard-file.jq, plugin/hooks/guard-bash.jq: writes to the files of another session's run denied
plugin/hooks/panel-sessions.js: Sessions tab rows
plugin/scripts/statusline.jq: leading / held by, 20 character cut
plugin/lib/cmd-loop.sh, plugin/hooks/stop.sh, plugin/skills/loop/SKILL.md: loop belongs to its starting session
docs/guards.md (Another session's run), docs/workflows.md (lease), docs/statusline.md, docs/panel.md (Sessions), docs/loop.md, docs/next.md (rename hint)
tools/l3-suite.sh: scenario_sessions
-->
