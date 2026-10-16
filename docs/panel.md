# The VBW panel

The panel is VBW inside Claude Code's own screen. It has two parts:

- **Comms**, the strip above the prompt: the helpers at work while a VBW
  workflow runs, or one line when VBW needs you (see [Comms](#comms)).
- **Mission Control**, a pane beside the conversation: where your project
  stands, in plain words, and seven tabs for the detail (see
  [Mission Control](#mission-control)). It opens by itself when a session
  starts in a VBW project.

VBW also adds a few short lines to places Claude Code already draws (see
[One-line notes](#one-line-notes)) and three instant commands (see
[Instant commands](#instant-commands)).

Mission Control's **Now** tab starts with these sentences:

```
Working on M1: First milestone.
milestone

5 of 12 requirements done.
requirements

VBW is building: P1.2, P2.1 (4 min so far).
build

about 10 min, until around 14:20
estimate, approximate

About 40 min left in the milestone.
estimate, approximate

This session has cost $1.42 so far.
session cost

Please approve the plan before VBW builds it.
your turn
```

Each sentence has a short technical term under it (`milestone`, `requirements`,
`build`, `session cost`, `your turn`), so you can learn the words VBW uses.
The panel shows these things, top to bottom:

1. **The milestone** you are working on.
2. **Progress:** how many of the milestone's requirements are done (proven by
   their checks, or accepted by you), counted as the status line counts them.
3. **What VBW is doing now:** planning, building (and which parts), checking
   the results, fixing what the checks found, mapping the project, or idle.
4. **Time left**, when VBW can estimate it: for the current step and for the
   milestone (see [Time left](#time-left)).
5. **What this session has cost** so far (see [Cost](#cost)).
6. **Whether it needs you, and for what:** approving the plan, checking a
   result by hand, giving the go-ahead to ship, saying what to build,
   deciding on a stuck fix, or answering a question. The line turns amber
   when it needs you.

The panel updates by itself, within a few seconds of a change. You do not
refresh it.

## Reading the panel at a glance

Read the panel from the top. The first two sentences say where you are. The
third says what VBW is doing. The estimate and cost lines say how long and how
much. The last sentence is the one that matters most: if it is amber, VBW is
waiting for you; if it says "Nothing is needed from you right now", you can
leave it running.

A typical panel while a plan builds, before VBW has history to estimate from:

```
Working on M1: First milestone.
milestone

5 of 12 requirements done.
requirements

VBW is building: P1.2 (4 min so far).
build

No end time yet: VBW has timed fewer than 3 steps like this here
estimate, no basis

This session has cost $1.42 so far.
session cost

Nothing is needed from you right now.
your turn
```

## Colours

Roles and states use different colours, so one colour never says two things.

**A state has one colour everywhere** (Comms, Mission Control and VBW Wrapped):

| State | Colour | Mark and word |
|---|---|---|
| running, or VBW needs you | amber | `● running` |
| done | green | `✓ done` |
| failed | red | `✗ failed` |
| quiet, cut off, idle | grey | `… quiet`, `■ cut off` |

Amber is the one colour for "look at this": a helper at work and a request for
you. A helper running past its usual time is amber on the Timeline, never red.
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
these colours: the progress sentence in green, the two time-left sentences in
amber, the session cost in purple, and the "needs you" sentence in amber when
VBW needs you. A sentence with no value in it ("No estimate yet", "The cost so
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

VBW reads this from the files Claude Code writes for each workflow run in this
session's own folder (`<Claude config folder>/projects/<project>/<session>/`):
which agents started, their type, their transcripts and the run's end. It finds
the run from the moment `/vbw:vibe` launches it, and again after a reload while
the run goes on. These files are Claude Code's own and undocumented: if they
change, Comms shows less, never an error.

**When VBW needs you**, Comms shows one line, timed from when VBW reached the
point where it needs you:

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

An approval older than the request, or a change to the record that has
nothing to do with it (for example a parked idea), leaves the line standing.
While a run is working, VBW shows no request at all, on Comms or in Mission
Control, and Mission Control says nothing is needed. After a ship, no "ready to
ship" text stays on Comms or in Mission Control.

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
Now │ Plan │ Proof │ Timeline │ Decisions │ Team │ Costs
```

The tabs stay at the top of the pane however long the content is. When the
content is taller than the pane, only the part under the tabs scrolls.

The tab row is always one line. In a narrow pane (40 columns, beside the
portrait) the tabs use short names: `Now Plan Proof Time Log Team Cost`.

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
- **Costs:** each VBW run of this session with its cost (the session cost added
  while the run was open, so "about"), by kind, and the session total. The list
  starts with the session: a new session starts again from zero.

### What's happening now

The **Now** tab opens on a framed box, drawn once, above everything else. It
holds the state sentence, the step with the time it started (`HH:MM`) and the
session cost. The state reads one of: planning, building (with its phase),
proving, checking, waiting for you (and for what), or nothing running. The box
follows a change of state within one refresh (about 2 seconds), with no other
event needed. When nothing is going on it says so:

```
+------------------------------------------+
| Nothing is running                       |
| Session cost $0.42                       |
+------------------------------------------+
```

### Clock times

Events and messages start with their clock time in brackets, so you can tell
when something began saying what it says:

```
[14:20] about 2 min, until around 14:22
```

Mission Control's need sentence starts with the time the gate was reached, and
the time-left sentences start with their own time. A helper card's state line
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
| A change to `.vbw/record.json` | one line saying what happened, for example `VBW · build run started`, instead of the full diff. Expand the row (ctrl+o) to see the full diff |
| The "workflow finished" row | `✓ VBW planning finished · 3 phases · 9 plans · 21 checks · 14m · ≈$4.10`; the full row shows in the expanded transcript (ctrl+o) |

The transcript Claude Code stores is never changed: these are drawings only.

## Instant commands

These answer at once, even while Claude is busy, and cost no model turn:

| Command | What it does |
|---|---|
| `/vbw-status` | Where the project stands: milestone, progress, what VBW is doing, what comes next |
| `/vbw-why` | Who holds the VBW run and since when, and what is blocked |
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
and **proof**. The same time shows in the status line, Comms, Mission Control
and VBW's own messages. The panel also estimates the time left for **the
milestone** (all the phases not yet passed). When nothing is running, it
estimates only the milestone. When no phase is left, it shows no milestone
estimate.

- **It is approximate.** "about 12 min" is whole minutes, never an exact
  figure. Under a minute it says "less than a minute". An end on another day
  names the day: "until around tomorrow 00:20". Times are 24-hour, local.
- **It needs history.** VBW gives an end time only after **at least 3 finished
  steps of the same kind** (for example 3 builds). With fewer, the panel says
  "No end time yet: VBW has timed fewer than 3 steps like this here" and shows
  no time. VBW never guesses. The milestone estimate also needs 3 finished
  builds and 3 finished checks; before that it says "No estimate yet: there are
  not enough finished steps to go on."
- **Time per part.** A build, a fix and a proof count their parts: the plans of
  a build, the fixes of a fix, the checks a proof really runs. VBW takes the
  median time per plan (or fix, or check) over the latest 10 steps of that kind
  that recorded parts, and multiplies it by this step's parts. A bigger build
  gets a longer time. Planning and QA have no parts: they use the median time
  of their latest 10 steps. With an even count, the median is the mean of the
  two middle values.
- **Later than usual.** When a step with parts runs past its end time, VBW moves
  the end to this run's own pace and shows
  "until around 14:35, later than usual". It can move again, and never earlier
  than the first end time.
- **N min late.** A step without parts (planning, QA) keeps its first end time
  and shows "until around 14:20, 6 min late" once it is a minute past it.
- **A proof inside a build or fix** shows as what the build or fix is doing
  ("proving 12 of 40 checks"); the build's own end time stays. A proof that
  reused every result ran nothing and has no time.
- **It comes from this clone's own history.** When a step finishes, VBW adds it
  (its kind, start, end, seconds and parts) to `steps.json` in your clone's git
  directory (`.git/vbw/steps.json`), keeping the latest 50 steps of each kind,
  so many steps of one kind never push out another. The file is private to your
  machine: it is not committed and not part of `.vbw/record.json`. To reset it,
  delete it: end times start again from none. A missing, unwritable or damaged
  file never fails a step; it only means no end time yet. The panel only reads
  it.
- **It never shows a negative time.** Past the end, the wording above says
  "later than usual" or "N min late" instead of a number of minutes left.

## Open and close it

In a wide window the panel opens by itself when a session starts in a VBW
project. In a narrow window Claude Code does not open a pane unasked, so run
`/vbw-panel`: it opens the panel at any width.

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
  in the panel never reaches your session.

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
not time spent waiting) as follows, measured on a developer Mac with Node 22:

| Check | Measured | Budget |
|---|---|---|
| Nothing changed | about 0.02 to 0.08 ms | 0.5 ms |
| A file changed, read and redrawn | about 0.04 to 0.2 ms | 0.5 ms |
| A need raised and the sound asked to play | measured by the same script | 0.5 ms |
| Comms and Mission Control both drawn, five helpers at work | about 0.4 ms | 0.5 ms |

The budget is about 12 times the cost of a plain check, to leave room for a busy
machine. These numbers come from the test stand-in for Claude Code, whose own
work is counted too, so they are an upper bound.

Check it yourself from a VBW checkout (needs `node`):

```
bash tools/bench-panel.sh
```

It prints each cost and the budget, and fails if a check is over the budget.
`VBW_PANEL_BUDGET_MS` changes the budget; `VBW_BENCH_RUNS` changes how many
checks it averages (default 200).
