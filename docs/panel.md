# The VBW panel

The panel is VBW inside Claude Code's own screen. It has two parts:

- **Comms**, the strip above the prompt: the helpers at work while a VBW
  workflow runs, or one line when VBW needs you (see [Comms](#comms)).
- **Mission Control**, a pane beside the conversation: where your project
  stands, in plain words, and eight tabs for the detail (see
  [Mission Control](#mission-control)). It opens by itself when a session
  starts in a VBW project.

VBW also adds a few short lines to places Claude Code already draws (see
[One-line notes](#one-line-notes)) and three instant commands (see
[Instant commands](#instant-commands)).

Mission Control's **Now** tab starts with a framed box that says what VBW is
doing, and then the sentences about the milestone:

```
+------------------------------------------------+
| VBW is building phase P1 (Show the cost).      |
| Current step: building P1.2, started at 14:08. |
| This step: about 12 min, until around 14:20.   |
| This session has cost $1.42 so far.            |
| session cost                                   |
+------------------------------------------------+

Working on M1: First milestone.
milestone

5 of 12 requirements done.
requirements

[14:08] Milestone end: about 40 min, until around 14:50.
estimate, approximate

Nothing is needed from you right now.
your turn
```

Each sentence has a short technical term under it (`milestone`,
`requirements`, `session cost`, `your turn`), so you can learn the words VBW
uses. The panel shows these things, top to bottom:

1. **What VBW is doing now,** in the box: planning, building (and which
   parts), proving, checking the results, fixing what the checks found,
   mapping the project, or nothing running. It also holds the **current
   step** with the time it started and, when VBW can estimate it, the time it
   should end (see [Time left](#time-left)), and **what this session has
   cost** so far (see [Cost](#cost)). When VBW needs you, the box holds the
   one sentence that says what for, the command to type, and since when it
   waits (see [What's happening now](#whats-happening-now)).
2. **The milestone** you are working on.
3. **Progress:** how many of the milestone's requirements are done (proven by
   their checks, or accepted by you), counted as the status line counts them.
4. **Time left for the milestone,** when VBW can estimate it.
5. **Whether it needs you:** while VBW needs nothing from you, the line
   "Nothing is needed from you right now" says so. When it does need you (to
   approve the plan, check a result by hand, give the go-ahead to ship, say
   what to build, decide on a stuck fix, or answer a question) that sentence
   is the box's, in amber, and the line below is left out: nothing is said
   twice.

The panel updates by itself, within a few seconds of a change. You do not
refresh it.

## Reading the panel at a glance

Read the panel from the top. The box says what VBW is doing, since when, how
long it should take and what the session has cost. When it is amber, VBW is
waiting for you: the box says what for and which command to type. The
sentences under the box say where the milestone stands. If the last one says
"Nothing is needed from you right now", you can leave it running.

A typical panel while a plan builds, before VBW has history to estimate from:

```
+-------------------------------------------------------------------+
| VBW is building phase P1 (First).                                 |
| Current step: building P1.2, started at 14:08.                    |
| No end time yet: VBW has timed fewer than 3 steps like this here. |
| This session has cost $1.42 so far.                               |
| session cost                                                      |
+-------------------------------------------------------------------+

Working on M1: First milestone.
milestone

5 of 12 requirements done.
requirements

Nothing is needed from you right now.
your turn
```

## Colours

Roles and states use different colours, so one colour never says two things.

**A state has one colour everywhere** (Comms, Mission Control and VBW Wrapped):

| State | Colour | Mark and word |
|---|---|---|
| running, or VBW needs you | amber | `● running` |
| refused | amber | `⊘ VBW refused` |
| done | green | `✓ done` |
| failed | red | `✗ failed` |
| quiet, cut off, idle | grey | `… quiet`, `■ cut off` |

Amber is the one colour for "look at this": a helper at work, a request for
you and a refusal ([Refusals](#refusals)). A helper running past its usual time is amber on the Timeline, never red.
Red is only for a failure. VBW Wrapped is a look back, so it draws no amber or
red.

**A role has a colour of its own.** None of them is green, red, amber or grey,
so a role is never mistaken for a state:

| Role | Colour |
|---|---|
| architect | magenta |
| lead | blue |
| dev | teal |
| QA | pink |
| scout | sky blue |
| debugger | violet |
| docs | lilac |

On Comms a working helper's mark is amber and its role name is in the role's
colour; a failed helper's `✗` is red.

Other colours: purple for the run's cost, green for progress, amber for time
estimates and for "VBW needs you", grey for secondary detail.

In Mission Control's **Now** tab, each sentence shows its key value in one of
these colours: the progress sentence in green, the two time-left sentences (the
step's, in the box, and the milestone's) in amber, the session cost in purple,
and the box's first sentence in amber when VBW needs you. A sentence with no value in it ("No estimate yet", "The cost so
far is not available") stays plain.

Colour never carries a state alone. Every state colour on Comms and on
Mission Control's cards sits beside its mark and word, so with colour turned
off (or if you cannot tell two colours apart) the panel reads the same.

## Judging the colours

Requirement R108 asks whether the colours make it easy to tell at a glance
which agent is which and what state each is in. Only you can judge that. Watch
Comms or the **Now** tab during a real VBW run, then record a verdict. The
colours are in `plugin/hooks/panel-palette.js`; the tables are in
[Colours](#colours).

How to judge:

- Can you tell the seven roles apart? They are all different hues.
- Can you tell the states apart: amber (running or needs you), green (done),
  red (failed), grey (idle or quiet)? **Quiet** and **cut off** are both grey,
  told apart only by their mark and word.
- Try a dark terminal and a light one. Pink, sky blue, lilac and amber are the
  colours most likely to wash out on a light background; grey is the most
  likely to fade on a dark one.
- A state is never colour alone: it also has a mark and a word. If you can
  tell two states apart by their mark and word but not by colour, that is fine.
  Judge colour on whether you can tell the roles apart and spot a state change
  without reading.

Record your verdict:

```bash
vbw req accept R108
vbw req reject R108 "scout and lead look the same on my light terminal"
```

A rejection needs a note saying what is hard to tell apart (which roles or
states, and on which terminal). The note becomes a fix.

## Comms

Comms is the strip directly above the prompt. VBW uses it only when there is
something to watch or something to decide; otherwise it is empty. A survey from
Claude Code always takes it first. (The pane beside the conversation is
[Mission Control](#mission-control).)

**While a VBW workflow runs**, Comms shows the crew, one row per helper:

```
VBW ▸ planning · Plan · 10m04s · ≈$3.20 this run · 1 done        [p] Mission Control
● architect  scope   ⠹ reading spec.md                              14:02
● lead       P53     ⠼ "Splitting R69 into two plans: the runner…"  14:03
+2 more · [m] Mission Control
```

- Each helper row shows the role as a word, in the role's colour (the step
  label next to it), what the helper is doing now (see
  [How activity reads](#how-activity-reads)), and the time it started
  (`HH:MM`).
- In the top line, the run's cost (`≈$3.20 this run`) is purple, and `N done`
  counts the helpers that have finished.
- A helper that finishes leaves Comms at the next redraw, with no wait. It
  stays in the `N done` count, and its card in Mission Control stops saying
  running at the same moment.
- A helper that fails stays as one red `✗` row until you open it in Mission
  Control. Then it leaves at the next redraw. If the run ends first, the
  failed helper you have not opened stays alone on Comms.
- When the run ends, the crew leaves Comms at once.
- A helper with no new step for 45 seconds is marked **quiet**, so a hang
  looks different from slow work.
- When there is no room for every row, the rest fold into one last line,
  `+N more · [m] Mission Control`, where N is exactly the number of helpers
  not shown. With little room the rows shrink, down to one summary line.
- The cost is the session cost added since the run started, so it is "about".

**In little room**, Comms shows lines in this order: the needs-you line, the
refusal line ([Refusals](#refusals)), then the helper line (`VBW ▸ ...`) while helpers work, then the step line.

- One row: the helper line carries the step's end time after its own parts,
  for example `VBW ▸ build · 1 working · 0m30s · until around 14:20`.
- Two rows: the helper line and the step line.
- Three or more rows: the header, the helper rows and the step line.
- A needs-you line with one row shows alone.
- The step line shows alone only when no helper works, for example during a proof.
- The step line and the weekly-limit line start with the time they began saying
  what they say, `[14:32] proving 12 of 40 checks · about 8 min, until around
  14:40`. The time does not move while the message stays the same, so the clock
  alone redraws nothing; in a narrow window the text is cut, never the time.
  The needs-you line, the all-checks-pass line and the helper rows already
  start with a time, and the `VBW ▸` line is a live count, so they carry no
  second one.

Comms never draws more rows than Claude Code gives it, so the prompt box stays
whole.

VBW reads this from the files Claude Code writes for each workflow run in this
session's own folder (`<Claude config folder>/projects/<project>/<session>/`):
which agents started, their type, their transcripts and the run's end. It finds
the run from the moment `/vbw:vibe` launches it, and again after a reload while
the run goes on. These files are Claude Code's own and undocumented: if they
change, Comms shows less, never an error.

**When VBW needs you**, Comms shows one line, timed from when VBW reached the
point where it needs you (the `since` of `vbw next`, docs/next.md, so a restart
or another session never moves it):

```
14:20 ⚑ VBW needs you · approve the plan
```

- The line has no buttons and nothing to press. Do what it says: run the
  command it names (for example `/vbw:approve`), or answer VBW's question.
- Every kind of request gets exactly one such line: approving the plan,
  approving edited test files, a result to check by hand, shipping, a blocked
  step, a fix limit, scope, the spec, the next milestone, converting a
  project, or `/compact` when the context is nearly full.
- The line stays while the request stands, and it is shown in amber.
- The hint line under the prompt still says what is waiting.
- Before a run, an amber warning appears when your weekly limit is past 80%. It is
  never red: red is only for a failure.

**When a message clears.** A message leaves as soon as it stops being true,
at the next redraw (within 2 seconds), with no other event needed:

| The line says | It clears when |
|---|---|
| Approve the plan | you approve the plan |
| Ready to ship | the milestone ships |
| A result to check | you answer the check |
| The next milestone | a new milestone starts |
| Say what to build | the requirements are written |
| Convert a VBW 1 plan | you convert it or choose to start fresh |
| A blocked step | the step is no longer blocked |
| A fix limit | the fix is no longer waiting on you |
| Scope | the changes outside the plan are cleared |
| Any request | a run starts (VBW holds the lease), or the request leaves VBW's next step |
| A question | you answer it |
| A refusal | you open the **Now** tab of Mission Control |

An approval older than the request, or a change to the record that has
nothing to do with it (for example a parked idea), leaves the line standing.
While a run is working, VBW shows no request at all, on Comms or in Mission
Control, and Mission Control says nothing is needed. After a ship, no "ready to
ship" text stays on Comms or in Mission Control.

### Refusals

When VBW refuses something inside a workflow (a `vbw` command an agent ran,
or a call a guard blocked), the agent reports it word for word in its result
([workflows.md](workflows.md#refusals-reach-the-user)). The panel shows it to
you, in amber, with the time the agent reported it:

```
14:02 ⊘ VBW refused · dev P1.1: vbw: apply refused: plan P1.1 is started
```

- **Comms** shows the newest refusal you have not seen as one line, under the
  needs-you line and above the helpers: the agent, then the refusal's first
  line (what was refused and why). It stays after the run ends, until you open
  the **Now** tab of Mission Control; a later refusal shows again.
- **Mission Control's Now tab** keeps the last run's refusals, the newest five,
  as amber sentences before the needs-you sentence, each whole on one line with
  its next step, under the term `refused`:

```
[14:02] ⊘ VBW refused, dev P1.1: vbw: apply refused: plan P1.1 is started Next: put it back as the record has it (vbw show plan P1.1)
refused
```

Amber says "look at this", not a failure: the agent usually takes the next
step the refusal names on its own. Red stays for failures. A guard's refusal
also reaches you as a message from Claude Code itself
([guards.md](guards.md#what-is-denied)).

## How activity reads

Comms and Mission Control say what an agent is doing as a plain intention, not the
raw command:

```
● editing app-topbar.tsx
● running tests
● recording P6.7 done
● running fix_topbar.py
```

The verb (`editing`, `running`, `recording`) is in the role's colour and the
object is dimmed. When an agent is writing text rather than calling a tool, the
Comms shows the end of that text in quotes, dimmed.

| The agent... | Shows |
|---|---|
| reads, edits or writes a file | `reading app.ts`, `editing app.ts` (the file name only) |
| searches files or the web | `searching <pattern>`, `researching <query or site>` |
| runs a test runner (`bats`, `pytest`, `npm test`, `cargo test`, `node --test`, ...) | `running tests` |
| runs a `vbw` command | what it does: `recording P6.7 done`, `proving the checks`, `reading the next step` |
| runs a script through Python, Node, Bash or another interpreter | `running <script file name>`, named by the file it runs |
| runs a script given with `-c` or `-e`, or from input | `running a script` |
| runs anything else | `running a command` |

Setup commands such as `cd`, `export` and `echo` are skipped: the line shows
the first command that does something. An intention is cut at 40 characters.

For shell commands the panel shows only a known phrase or a bare file name,
never the command's arguments or flags, so a secret on a command line does not
reach the screen.

## Mission Control

Mission Control is the pane. Its tabs run across the top, after the VBW
portrait (a picture on terminals that draw images, such as kitty and Ghostty;
the word `VBW` elsewhere); press one to switch:

```
Now │ Plan │ Proof │ Timeline │ Decisions │ Team │ Sessions │ Costs
```

The tabs stay at the top of the pane however long the content is. When the
content is taller than the pane, only the part under the tabs scrolls.

The tabs follow one rule: a tab name is never split, and a row is never wider
than the pane. The layout with the fewest rows wins; at an equal number of rows
the full names win over the short ones (`Now Plan Proof Time Log Team Sess Cost`).

- At 90 or more columns the full names fit on one row (the portrait sits beside
  them from 91 columns).
- At about 64 columns (beside a 200-column window) the full names take two rows,
  beside the portrait.
- At 40 columns (the minimum) the short names take two rows.

The portrait is left out when keeping it would cost a tab row or a full name,
and when the pane is short.

Mission Control never draws more rows than the pane has. When Claude Code
reports no height for the pane, it has one fixed height of at most 30 rows.
If the content is taller, the last line says how much is left out:

```
+14 more · open Mission Control
```

A pane with room for everything has no such line. Open the pane itself (or
scroll it) to read the rest.

- **Now:** a framed [what's happening now](#whats-happening-now) box above everything else, then the sentences above, the sound switch, [What's next](#whats-next), then the running workflow as
  columns of agent cards by phase. Each card has a frame in its agent's role
  colour, its state as a coloured mark and word (`● running`, `✓ done`,
  `✗ failed`, `… quiet`), what the agent is doing, and its tokens, dimmed. Two
  agents of different roles never look the same. Press a card for that agent's
  model, time, current step and result.
- **Plan:** one button per phase; each shows its goal, its plans with their
  files, and its checks with their commands.
- **Proof:** one square per approved check (green passed, red failing, grey not
  run). Press a check for its last output.
- **Timeline:** one lane per agent against the run's clock, the three slowest
  marked, and past steps of the same kind against their usual time.
- **Decisions:** the milestone's decisions, newest first.
- **Team:** which model each role uses, the profile, autonomy and rigor, with
  buttons that fill `/vbw:config` and `/vbw:profile`.
- **Sessions:** the chats open on this project, and which one holds the run (see
  [Sessions](#sessions)).
- **Costs:** each VBW run of this session with its cost (the session cost added
  while the run was open, so "about"), by kind, and the session total. The list
  starts with the session: a new session starts again from zero.

### Sessions

The **Sessions** tab lists every chat in Claude Code's own list that belongs to
this project (its folder or one inside it), newest first. Chats of other
projects and sibling folders are left out. A chat that has several files in the list shows once, from the newest. Each row shows:

```
vbw · myapp      ● holds the run · build    idle    14:32
                 claude --resume 3f9c1a2e-...
```

- the chat's name, cut to the pane width with an ellipsis;
- a state word and the time it was last active (`HH:MM` on your clock; a chat last active on another day says `yesterday 14:20` or the weekday, `Monday 14:20`, as the rest of the panel does);
- `claude --resume <session id>`, ready to copy.

The row of the chat you are in says `this chat`. The row of the chat that holds
the run shows `● holds the run` and the run kind (build, plan, ...) in the
accent colour. If the holder has no entry in the list, it is still shown, taken
from the run's lease, as `closed or not seen`.

When there is nothing else to show (no list, or no other chat on the project),
the tab says `No other chats are open on this project`.

The tab is read-only: no button, nothing is sent to a chat, nothing is written.
The list is re-read on the panel's tick only while the tab is shown or a run
holds a lease. A malformed entry skips its own row and never breaks the panel.

This tab is the one place the panel reads outside the project: Claude Code's
own list of chats, read-only. See the paragraph on it in
[guards](guards.md#sessionstart).

### What's happening now

The **Now** tab opens on a framed box, drawn once, above everything else. It
holds three things:

- **The state,** one sentence: planning, building (with its phase), proving,
  checking, fixing, mapping, or nothing running. When another chat holds the
  run, it ends with `, held by <name>` (the chat's name, else the first 8
  characters of its id); in the chat that holds the run it is unchanged.
- **The step:** its name and the time it started (`HH:MM`) and, on the next
  line, when it should end (`This step: about 12 min, until around 14:20.`, or
  `No end time yet: ...` while VBW has no history to estimate from; see
  [Time left](#time-left)). The name comes from the step VBW is timing
  (`building P1.2`); without it the line only gives the start
  (`Started at 14:08.`), since the state sentence has said what VBW is doing.
- **The session cost** (see [Cost](#cost)).

When VBW needs you, the state is replaced by the one sentence that says what
for, in amber and bold, and the step by since when it waits:

```
+-----------------------------------------------+
| Please approve the plan before VBW builds it. |
| Type /vbw:approve.                            |
| Waiting since 14:08.                          |
| This session has cost $1.42 so far.           |
| session cost                                  |
+-----------------------------------------------+
```

The command is the one that answers it: `/vbw:approve` for a plan,
`/vbw:verify` for a result to check by hand, `/vbw:convert` for a VBW 1 plan,
and `/vbw:vibe` for everything else. A question from VBW has no command (you
answer the question), and the "context nearly full" warning already names
`/compact` in its sentence. Whatever the box says is not said again below it:
no second "VBW is building" sentence, no second end time or cost, no
"needs you" line, and no "No VBW workflow runs in this session right now"
under a box that says nothing runs (that line appears only while another chat
holds a run, because then the box says VBW is working and the line says it is
not working here). The box follows a change of state within one refresh (about
2 seconds), with no other event needed. When nothing is going on it says so:

```
+-------------------------------------+
| Nothing is running.                 |
| This session has cost $0.42 so far. |
| session cost                        |
+-------------------------------------+
```

### Clock times

Events and messages start with their clock time in brackets, so you can tell
when something began saying what it says:

```
[14:20] about 2 min, until around 14:22
```

The box says since when VBW has been waiting for you, and the time the current
step started. The milestone's time-left sentence starts with its own time. A helper card's state line
starts with the time the helper started (while running) or ended (done or
failed). The all-checks-pass line in Comms starts with the time of the proof,
and What's next shows when its recommendation was written. A message keeps the
time it began saying what it says: three minutes of clock alone redraw
nothing.

### What's next

The **Now** tab has a **What's next** section with the recommendation VBW
stored the last time it was asked what to work on next. It shows the same
things, in the same order, as `vbw status`:

```
What's next
Refunds for paid orders · small
  Customers ask for it most this month.
  Gift cards · large
  Dark mode · medium
written 2026-10-09
[Suggest next]
```

- The **top pick**, with its size (`small`, `medium` or `large`) and the reason
  VBW gave for it.
- Up to two **runners-up**, each with its size, one per line.
- On each What's next row (the top pick and each runner-up) the item line is a
  **button**, followed by a size **chip**; only the item line is pressable, the
  reason under it is plain text. Pressing the item fills `/vbw:vibe` with the item's `T` or `R` id, or
  with its text when it has no id. It only fills the prompt and never sends:
  you press Enter.
- When the recommendation was **written**, as `[HH:MM]` in the panel.
- Before any recommendation is stored, one line says there is **none yet**.
- When the recommendation found nothing to pick, one line says **the backlog
  is empty**.
- Long lines are cut to the pane's width. A stored recommendation the panel
  cannot read hides the pick lines; the section and its button stay.

The section follows the record: a new recommendation appears within a few
seconds, with no restart.

**Suggest next** asks for a fresh recommendation. It puts
`/vbw:vibe what's next` in the prompt and never sends it: you press Enter, as
with every other button. The request costs one Architect run.

The section has two touches of colour, both from the palette above and both
only with full motion (see [Motion](#motion)):

- The title **shimmers** slowly.
- The top pick gives a soft **pulse** when a new recommendation arrives.

Both settle within a few seconds. Neither moves for a recommendation you have
already seen, so opening the panel again does not replay them. With `motion`
set to `calm` or `off`, or left unset with an interview level whose default is
not `full`, the section is still. Whether the effect is subtle and elegant
(R125) is yours to judge: watch a new recommendation arrive, then
`vbw req accept R125` or `vbw req reject R125 "<what is off>"`.

A new recommendation is also **marked** as new. The mark appears 10 seconds
after it arrives, when the shimmer has settled, and stays until you have seen
it; opening the Now tab counts as seen. At full motion it is a mark after the
shimmer; at `calm` the mark does not move; with motion `off` only the word
`new` shows. The same mark stays on a newly failed helper's card in Mission
Control until you open it, and on a new needs-you line in Comms until you open
its tab. Seen stays seen after a restart, and unseen stays new: the panel
keeps this under `vbw-panel.*` in your own store, never in the project.

When a milestone ships, Mission Control opens on **VBW Wrapped**: the
requirements proven, the checks passing, the agents and fix rounds, the time
the milestone's steps took, its cost and its fastest and slowest steps. The
agents and the cost count only the runs this session saw; what VBW cannot know
says "unknown" or is left out. Press any tab to leave it.

## One-line notes

VBW adds a few words to places Claude Code already draws. Each one keeps
Claude Code's own drawing whenever VBW has nothing to say.

| Where | What VBW adds |
|---|---|
| The spinner while a turn runs | ` · VBW building P53.2 (2/5)…` while a VBW run works |
| The hint line under the prompt | `VBW: planning 10m`, `VBW needs you: /vbw:approve` or `VBW next: /vbw:vibe` |
| The footer's mode labels | `VBW auto ⟳ 3/10` during an autonomous run, else the profile (`VBW careful`, `VBW standard`, `VBW fast`) |
| The notes under the logo, once | `VBW M11 · 1/15 · next: /vbw:vibe` |
| A question VBW asks | `VBW · a decision for M11` above the question |
| The line that closes a turn | `VBW · plan approved · 3s` after a turn that moved VBW on |
| The Workflow row | `VBW planning · started 16:33 · [p] watch live` |
| A `vbw` command's row | what it did: `VBW · recorded P53.1 done` (its output stays below) |
| A change to `.vbw/record.json` | one line saying what happened, for example `VBW · build run started by <name>` (`by this chat` in the chat that holds the run; the first 8 characters of the id when no name is known; unchanged when the run has no holder), instead of the full diff. Expand the row (ctrl+o) to see the full diff |
| The "workflow finished" row | `✓ VBW planning finished · 3 phases · 9 plans · 21 checks · 14m · ≈$4.10`; the full row shows in the expanded transcript (ctrl+o) |

The transcript Claude Code stores is never changed: these are drawings only.

## Instant commands

These answer at once, even while Claude is busy, and cost no model turn:

| Command | What it does |
|---|---|
| `/vbw-status` | Where the project stands: milestone, progress, what VBW is doing (with the same `held by <name>` as the Now box), what comes next |
| `/vbw-why` | Who holds the VBW run, by name, and since when, and what is blocked: `held by this chat ("<name>")` or `held by "<name>"`, with the id in brackets only when no name is known; then the file count and `wait for it` |
| `/vbw-todo [idea]` | Parks an idea for later. With no text it takes the text you selected. VBW's own `vbw todo add` writes it |
| `/vbw-panel` | Opens Mission Control |
| `/vbw-sound` | Turns the "needs you" sound on or off |

## Cost

The cost is **one line** that shows what the **current Claude Code session**
has cost so far, in dollars. It is not a project total and not a history: a new
session starts again from zero. There is no breakdown by tokens, cache or
model.

The number comes from Claude Code and follows it within a few seconds. When
Claude Code gives no cost, the line says so instead of showing a number:

```
The cost so far is not available.
cost, not available
```

The panel never guesses a cost.

## Time left

Every long step shows what it is doing and when it should end, as a clock time:

```
Building P1.2, P2.1 · 1 of 2 · about 12 min, until around 14:20
```

Five kinds of step get an end time: **planning**, **build**, **fix**, **QA**
and **proof**. The same step time shows in the status line, Comms, Mission
Control and VBW's own messages. In a one-row Comms, the step's time sits on
the helper line. Mission Control (and the chat message VBW says before a step)
also shows when **the milestone** should end, the "road": the
step now running plus everything still ahead until the milestone is done. The
status line shows the step's time only, never the milestone's. When no phase is
left, there is no milestone end.

```
Milestone end: about 36 min, until around 14:56, counting 2 fix rounds per standard phase (the usual here)
```

- **It is approximate.** "about 12 min" is whole minutes, never an exact
  figure. Under a minute it says "less than a minute". Over an hour it reads
  "about 2 h 36 min". An end on another day names the day: "until around
  tomorrow 00:20". Times are 24-hour, local.
- **It needs history.** VBW gives an end time only after **at least 3 finished steps**
  of the same kind (for example 3 builds). With fewer, the panel says
  "No end time yet: VBW has timed fewer than 3 steps like this here" and shows
  no time. VBW never guesses.
- **Time per unit at a tier.** Each kind of step is sized by its own unit, and
  VBW takes the median time per unit over the latest 10 finished ones **at the
  same tier** (an older plan or another tier does not count):
  - a build: the time **per unit of work** of the plan's tier, times the plan's
    work: its tasks plus its breaks (the rules it owes the mutation check, one
    break each; none at express), so a bigger plan, or one with more rules to
    break, gets a longer time. A build takes a high quantile, not the median
    (below: a wave waits for its slowest plan);
  - a fix round: the median wall time of a **fix round** at the tier, whatever
    the number of fixes;
  - a proof: its units (see below);
  - QA: the median time **per phase** checked at the phase's tier, added over
    the phases it checks;
  - planning: the median time **per open requirement**, times the requirements
    to plan now.

  With an even count, the median is the mean of the two middle values.
- **Idle time is not work.** The history keeps when a step started and ended,
  not what it waited for, so a run left open overnight or waiting for you is
  recorded at its whole length. Before any estimate, VBW leaves out a step that
  took more than 8 times the median seconds per part (per plan, requirement or
  phase) of its kind, while at least 3 steps remain. A wait shorter than that
  still counts, and a kind whose recent steps all waited has nothing to compare
  with; deleting `.git/vbw/steps.json` starts the estimates again.
- **The fallback ladder.** A unit with fewer than 3 finished ones at its tier
  falls back one rung at a time: first the median time per plan (or per phase)
  at that tier, then the median of any tier, then the plain median time of the
  step as older VBW kept it (builds that recorded only parts use the median time
  per plan times the plan count). A build's first rung counts only plans that
  recorded their breaks; with fewer than 3, it takes the time per task of the
  plans that recorded tasks, then per plan at the tier, then per plan of any
  tier, each at the same quantile. Each rung needs at least 3 finished units;
  with fewer than 3 in all, there is no time and the panel says so.
- **Side-by-side plans are not added.** Plans of one wave build at the same time
  (in parallel), so a wave takes its longest plan's time, never their sum.
- **A wave waits for its slowest plan.** Plan times vary widely (one plan of a
  wave can take ten times another), so each plan is timed high: at the upper
  quartile of its tier's time per unit for a lone plan, and higher the more plans
  build side by side, the quantile 0.75^(1/n) for n plans (0.87 for two, 0.91 for
  three, 0.93 for four). That is the time 3 waves in 4 end within when plans
  vary on their own. A wave that runs past it moves its end (later than usual,
  below).
- **A proof's time comes from its units.** Every proof records each unit it ran
  (a check, a test file, a project command) and that unit's own seconds in
  `steps.json`; `runs.json`, next to it, keeps each unit's last run. A unit's
  cost is the fastest it ran in the latest 10 proofs that recorded units or in
  its last run: a busy day's slow run never sets the promise, and a proof that
  runs late moves its end as it goes (later than usual, below). A proof is
  expected to take the sum of its units' costs, times the **learned ratio**:
  those proofs' total wall time over their total unit time, so one proof of two
  units cannot skew it (parallel lanes and this machine's load are learned, not
  assumed). A unit never run before counts as the median of the proof's known
  costs. Without such proofs, the time per unit of older proofs is used; with
  fewer than 3 finished proofs, there is no time.
- **The road's pieces.** The milestone end adds up: the build waves still to
  build (a wave already built leaves the road), one proof per wave over the
  phase's checks not yet passed (a built phase whose checks are not passed still
  counts one proof), QA where the phase's tier asks for it, and the **usual fix
  rounds**, each counted as one fix round plus one proof plus one QA recheck.
- **The usual fix rounds.** For each tier, the usual number is the rounded
  median of `outcome.fix_rounds` over the latest 10 finished phases of that tier
  (1, 2, 2 and 5 give 2). It needs at least 3 finished phases of the tier. The
  sentence names what it counted: "counting 2 fix rounds per standard phase (the
  usual here)". With fewer than 3 finished phases of a tier, the road counts no
  fix rounds for it and says so: "counting no fix rounds: fewer than 3 finished
  deep phases here".
- **Before planning.** Until the work is planned, the road is the planning step
  alone: "Milestone end: planning about 2 min, until around 14:22; the rest
  follows once the work is planned". VBW never guesses unplanned work.
- **No milestone end time yet.** When any piece the road needs has no basis, the
  road has no end and no time, and the sentence names the missing kind: "no
  milestone end time yet (VBW has timed fewer than 3 plans here)". A made-up time
  never appears. Every shape the history has had is read; an entry of a shape
  VBW never wrote is skipped, and a piece that still cannot be timed says so
  ("VBW could not time the plans here from its step history") instead of
  dropping the milestone end.
- **Later than usual.** When a step with parts runs past its end time, VBW moves
  the end to this run's own pace and shows
  "until around 14:35, later than usual". It can move again, and never earlier
  than the first end time. The milestone end moves by the same amount at once.
- **N min late.** A step without parts (planning, QA) keeps its first end time
  and shows "until around 14:20, 6 min late" once it is a minute past it.
- **A proof inside a build or fix** shows as what the build or fix is doing
  ("proving 12 of 40 checks"); the build's own end time stays. A proof that
  reused every result ran nothing and has no time.
- **It comes from this project's own history, only.** When a step finishes, VBW
  adds it (its kind, start, end, seconds, parts, and for a build each plan's
  tier and tasks) to `steps.json` in your clone's git directory
  (`.git/vbw/steps.json`), keeping the latest 50 steps of each kind, so many
  steps of one kind never push out another. Entries written before stay
  readable. The file is private to your machine and to this project: it is not
  committed, not part of `.vbw/record.json`, and never shared with other
  projects (no computer-wide history, D433). To reset it, delete it: end times
  start again from none. A missing, unwritable or damaged file (also
  `runs.json`) never fails a step; it only means no end time yet. The panel only
  reads: it works no milestone time out itself and shows the road the kernel
  wrote.
- **It never shows a negative time.** Past the end, the wording above says
  "later than usual" or "N min late" instead of a number of minutes left.

## Open and close it

The panel opens by itself when a session starts in a VBW project, as far as
Claude Code allows: it seats a pane that nobody asked for only in a window at
least 144 columns wide (110 once you have opened the panel yourself and not
closed it by hand since). In a narrower window the panel stays open but
undrawn, and appears when the window is widened to that width. `/vbw-panel`
opens it at any width. If the panel could not be started while the session
began (Claude Code's per-user store was not ready), the next prompt, question
or workflow starts it.

The panel asks for a quarter of the terminal's width (never under 40
columns). It asks once per session, after its first drawing, and never takes
the keyboard. `/vbw-panel` opens at a quarter of the width of the terminal you
typed it in. A width you set by dragging the pane's edge always wins: Claude
Code keeps it, VBW never asks again, and VBW never stores a width as your
choice. Drawn on the main screen (not as a side pane), or where the width is
not reported, the panel asks for nothing.

If you close the panel yourself, it stays closed, in later sessions too, until
you open it again with `/vbw-panel`. VBW keeps this choice in Claude Code's
per-user store, never in your project, and opening or closing changes no file
of the project.

`/vbw:panel` checks your Claude Code version and tells you whether the panel
and its sound are available.

## The sound

VBW plays a short sound when Claude Code's own question menu opens (the
`AskUserQuestion` menu where you pick an answer). It plays **once per
question**: not when the menu is redrawn, not when you answer or the menu
closes, and not for a gate on its own. A gate that stands in the record or in
`next.json` with no question open makes no sound; if one stands when a question
opens, you still hear one clip. A second question plays once more. Each time
VBW picks one clip at random from the sounds shipped with it, in
`plugin/assets/audio/<character>/` (mp3 files).

### The notification

When the menu opens, VBW also raises one native notification, titled `VBW`,
with a plain sentence naming what it needs (for example, that it has a question
for you). It never fires twice for one question.

VBW raises the same kind of notification, without a sound, once for each new
[What's next](#whats-next) recommendation. One you have already seen raises
none after a restart; a newer one raises one.

### Turning them off

The sound and the notification share one switch. It is **on by default**. To
turn both off or on:

- click the **Turn off** / **Turn on** button in the panel, or
- run `/vbw-sound` (it switches; `/vbw-sound off` and `/vbw-sound on` set it).

With the switch off, nothing plays and no notification is raised. The choice is
remembered. It is yours alone: it is kept in Claude Code's per-user store on
your own machine, never committed, never in the project and never in
`.vbw/record.json`. A test session plays and raises nothing, and uses only
`test.*` keys in that store, never yours.

### When they are missing

If Claude Code has no notifications, or the sound cannot play (no player, no
file), VBW does nothing in their place: no toast, log line, status or notice,
and nothing breaks. The sound needs the panel, so it needs Claude Code 2.1.287
or newer.

## Motion

How much the panel animates is a project setting, shared through git:

```bash
vbw config set motion full     # crew sprites and celebrations
vbw config set motion calm     # dots and spinners, no confetti
vbw config set motion off      # static text
vbw config set motion default  # let your interview level pick
```

What each level shows:

| | `full` | `calm` | `off` |
|---|---|---|---|
| The What's next title and a new top pick | shimmer and pulse, then settle | still | still |
| Each working agent in Comms (the first 3 only) | a small figure in its role's colour, posed by what it does (reading, editing, running a command, writing), moving about 10 times a second while the run works | a dot in its role's colour and a spinner that steps once a second | a dot and a still `·` |
| A new agent starts | its row in Comms flashes in its role's colour for about a second | no flash | no flash |
| A phase passes QA | about 1.5 s of confetti in Comms | nothing | nothing |
| All checks pass | one green sweep across the top of the Proof tab, and `✓ All checks pass` in Comms for a minute | `✓ All checks pass` in Comms for a minute | nothing |
| A milestone ships | Mission Control opens on VBW Wrapped | the same | the same |

The flash shows the role and label of the new row with its colours inverted. It
needs `full` motion: set it with `vbw config set motion full` (see above). At
`calm` and `off` a new agent's row appears without it.

At most 3 working helpers get a figure at full motion; the other helpers are
text rows. A finished helper leaves Comms, and a failed one is a red `✗` text
row, so Comms never draws a done, failed or quiet figure. A figure needs three
rows of Comms; with less room Comms shows dots. They move only while a VBW run works and Comms shows them, and
stop when the run ends. Figures, confetti and the sweep are drawn on the
terminal only; other surfaces show the dots. VBW Wrapped is information, not
decoration, so it opens at every level.

Unset, the panel picks `full` if you told the interview you have never coded
or write small scripts, and `calm` otherwise (also before the interview). In
test mode it is always `off`, so test runs draw the same thing every time.
`vbw config` shows the setting.

## What it needs

The panel needs **Claude Code 2.1.287 or newer** (check with
`claude --version`; update with `claude update`).

- **Comms, above the prompt** (the crew and the needs-you line) needs **2.1.290 or
  newer**: earlier versions redraw Comms forever when it changes height. On
  2.1.287 to 2.1.289 the pane, the one-line notes and the commands work, and the
  Comms stays Claude Code's own.
- **Older Claude Code:** there is no panel and no error. Everything else in
  VBW, including the status line, works as before.
- **Outside a VBW project** (no `.vbw/record.json`): there is no panel and no
  error. When `/vbw:vibe` sets a project up during the session, the panel comes
  on at its first question (or your next prompt), with no restart.
- **Anything unexpected inside the panel:** it stays out of the way. An error
  in the panel never reaches your session. The hooks that sit in the way of
  something you do (closing the pane, a command, a question, a prompt, a
  workflow) each have a fallback: when one fails, the event goes on as if the
  panel were not there, a command says in a sentence that it did not work, and
  a question that was being shown is no longer counted as open. Claude Code
  reports the failed hook by name; VBW adds no message of its own.

## What it reads and what it costs

The panel only reads local files: `.vbw/record.json`,
`.vbw/runtime/next.json` and this session's `.vbw/runtime/auto.<session>.json`
in your project, `steps.json` in your clone's git directory, and the workflow
run files in this session's own folder under the Claude config folder (found
from `CLAUDE_CONFIG_DIR`, else `HOME`; no other environment variable is read).
It asks Claude Code for the session cost, context fill and weekly limit,
read-only. It never writes and never uses the network. The one program it runs
is VBW's own `vbw todo add`, when you type `/vbw-todo`. It reads a file again
only when that file's size or modification time has changed, and redraws only
when what it shows changes (while agents work, that is every check).

It checks every 2 seconds. Each check costs CPU time (user plus system,
not time spent waiting) as follows, measured on 2026-10-24 on an Apple M1
Max with Node 22 while other work kept the machine at a load of 4 to 6 (8
runs of the script below, each case after 1000 warm-up checks):

| Check | Measured | Budget |
|---|---|---|
| Nothing changed | about 0.04 to 0.07 ms | 0.5 ms |
| A file changed, read and redrawn | about 0.11 to 0.14 ms | 0.5 ms |
| A need raised and the sound asked to play | about 0.10 to 0.17 ms | 0.5 ms |
| A running step's note changed | about 0.06 to 0.13 ms | 0.5 ms |
| The session cost and the step history changed | about 0.09 to 0.15 ms | 0.5 ms |
| A new recommendation drawn under What's next | about 0.07 to 0.16 ms | 0.5 ms |
| Comms and Mission Control both drawn, five helpers at work | about 0.22 to 0.32 ms | 0.5 ms |

The budget leaves room for a busy machine. These numbers come from the test
stand-in for Claude Code, whose own work and file writes are counted too (a profile
put them at about 40 percent of the last row), so they are an upper bound. The first few hundred checks
of a freshly loaded panel cost up to twice as much while V8 compiles it; the
figures are for the panel after that, which is where a session spends its time.

Check it yourself from a VBW checkout (needs `node`):

```
bash tools/bench-panel.sh
```

It prints each cost and the budget, and fails if a check is over the budget.
`VBW_PANEL_BUDGET_MS` changes the budget; `VBW_BENCH_RUNS` changes how many
checks it measures (default 200, in 5 windows, reporting the median window);
`VBW_BENCH_WARM` changes the warm-up (default 1000 checks).
