# Known issues and roadmap

What is known to be wrong or unfinished in VBW 2 today, what is planned, and what is still only an idea. Larger open ideas that need design work are in [ideas.md](ideas.md).

Nothing here is a promise. An item is evidence of a problem; the fix named under it is the current plan and may change when someone works on it. Every item is judged against VBW's design for all its users, like any other request (see the first rule in [CONTRIBUTING.md](../CONTRIBUTING.md)).

## How to use this page

- **You hit one of these.** The workaround, if there is one, is under the item.
- **You found something that is not listed.** Open an issue with the [bug report template](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues/new?template=bug_report.md). Run `/vbw:doctor` first and paste its output.
- **You want to fix or build one.** Open a GitHub issue for it (or comment on the existing one) in [swt-labs/vibe-better-with-claude-code-vbw](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues) before you start, so two people do not build the same thing. Then follow "Picking up an item" in [CONTRIBUTING.md](../CONTRIBUTING.md#picking-up-an-item-from-the-roadmap).
- **You disagree with a plan.** Say so in an issue, with the problem you see. A different solution to the same problem is welcome.

Status words:

- **Known issue:** VBW behaves worse than its documentation says.
- **Planned:** we intend to do it. No user-visible failure is behind it.
- **Idea:** we are weighing it. It may be adopted, reshaped or declined.

## At a glance

| Item | Status | Affects | Workaround |
|---|---|---|---|
| [The loop's time budget follows the size label](#the-loops-time-budget-follows-the-size-label) | Known issue | Loops | Re-run the item |
| [Time estimates absorb idle time](#time-estimates-absorb-idle-time) | Known issue | Estimates | Delete `steps.json` |
| [Heavy checks each use every core](#heavy-checks-each-use-every-core) | Known issue | Cargo, make, similar | Lower `check_jobs` |
| [Slot store edge cases](#slot-store-edge-cases) | Known issue | Sandboxes, many runs | None needed |
| [Unit times are whole seconds](#unit-times-are-whole-seconds) | Known issue | Proof time reports | None needed |
| [Panel drawing headroom](#panel-drawing-headroom) | Planned | Slower Macs | None needed |
| [Real-user scenarios for four features](#real-user-scenarios-for-four-features) | Planned | Test coverage | Not applicable |
| [Cost per correct outcome](#cost-per-correct-outcome) | Idea | Everyone | Not applicable |

## Known issues

### The loop's time budget follows the size label

**What.** When the loop opens an item, its time budget is twice the median time of shipped items with the same size label, or 2, 4 or 8 hours for small, medium and large when there is no history ([loop.md](loop.md#the-time-budget)). The label is a guess made before planning. An item labelled small that turned out to be eleven plans in three phases was stopped at the small-item budget. Time lost to dropped network connections or to waiting for you counts as time, so it can also stop a healthy item.

**Who and when.** Anyone running `/vbw:loop` over a backlog with items whose size was guessed wrong.

**Workaround.** The stop keeps all the work and parks nothing. Run `/vbw:loop THE_ITEM` again, or finish the item with `/vbw:vibe`. Give items an honest size (`vbw todo add --size`, `vbw todo sort`).

**Plan.** Once an item is planned, its budget becomes twice the kernel's estimate of its road ([panel.md](panel.md#time-left)). The stuck test counts progress (plans done, fixes closed), so waiting is not grinding. Before planning, the size default stays.

**Where.** `plugin/lib/loop-step.sh` (`loop_item_budget`); the estimate comes from `plugin/lib/road.jq`.

### Time estimates absorb idle time

**What.** A build or fix step whose run stayed open overnight, or while waiting for you, is recorded at its whole length (13, 18 and 40 hours have been seen). The estimate for later steps is the median of recorded times, so it comes out hours too long: a proof was announced as "about 12 hours".

**Who and when.** Anyone who leaves a run open while away. The wrong figure shows in the status line, Comms, Mission Control and VBW's messages.

**Workaround.** Delete `.git/vbw/steps.json` in the clone. Estimates then start again from none ([panel.md](panel.md#time-left)).

**Plan.** Time only active work, excluding waits for you, approvals and other runs, or drop steps far beyond their size.

**Where.** `plugin/lib/steps.sh` (what a step records); `plugin/lib/steps-expect.jq` (the estimate).

### Heavy checks each use every core

**What.** Test commands such as `cargo test` and `make` each try to use every core. VBW runs several checks at once (up to `check_jobs` and the computer-wide limit, [proof.md](proof.md#checks-run-in-parallel)), so several of them together can overload the machine. Load averages from 23 to 66 have been seen.

**Who and when.** Projects whose checks are heavy build-and-test commands, when a proof runs many of them at once.

**Workaround.** Lower the number of checks at a time: `vbw config set check_jobs 2` (or `1`). A check can also run by itself with the `alone` mark ([proof.md](proof.md#checks-that-run-alone)).

**Plan.** Give each command its share of the cores through the standard variables (`CARGO_BUILD_JOBS`, `MAKEFLAGS`, `GOMAXPROCS`), or let a check declare a cores mark. Not decided: it depends on measuring how much each tool really uses.

**Where.** `plugin/lib/checks.sh`; the limit logic in `plugin/lib/slots.sh`.

### Slot store edge cases

**What.** The computer-wide limit is kept in a small shared store (`slots.json` in the Claude config folder, [proof.md](proof.md#the-computer-wide-limit)). Three weaknesses remain, none breaking a requirement:

1. Two runs that find the same dead lock owner can both delete the lock and briefly allow one slot too many. The fix is to take the lock over with an atomic rename.
2. When the lock cannot be created but the folder looks writable (a sandbox, a full disk), the first step retries for about 30 seconds before saying it cannot write. It should detect this at once.
3. Smaller: `vbw plan done` may print the "limit was not in force" line twice on an unwritable store and never prints the end-of-run waited line; a waiting entry left by a unit that lost the store can be handed a slot it never uses, which stays held until its run exits.

**Who and when.** Sandboxed sessions, full disks, and many runs at once. The effect is a pause or one extra check at a time, never a wrong result.

**Workaround.** None needed. `check_jobs` still applies.

**Plan.** A test for each case, then the fixes.

**Where.** `plugin/lib/slots.sh` (`slots_lock`, `slots_open`).

### Unit times are whole seconds

**What.** VBW times each unit of a proof (a check, a test file, a project command) in whole wall-clock seconds. A unit that takes 50 ms can be counted as 0 s or 1 s depending on whether it crosses a second, so the "slowest units" line and `vbw show evidence` can name a different order or total between two runs of the same work, and "each under a second" is not always printed when it is true.

**Who and when.** Everyone reading the time reports. Verdicts, reuse decisions and the budget's effect (a report, never a failure) are not affected.

**Plan.** Time units with a sub-second clock where one is available, as the proof's own steps already are.

**Where.** The unit timing in `plugin/lib/checks.sh` and the report in `plugin/lib/unittime.sh`.

## Planned improvements

### Panel drawing headroom

**What.** Drawing Comms and Mission Control together measured 0.47 to 0.51 ms of CPU against a 0.5 ms budget once the tab layout moved to whole rows. It now measures about 0.42 to 0.44 ms on a loaded developer Mac, and single runs on a busier machine still reach 0.51 ms. About a fifth of the figure is V8 compiling code on its background threads during the bench's 200 refreshes of a freshly loaded panel, and about a third is the test stand-in's own work.

**Who and when.** A busy or slower Mac can still fail the release benchmark now and then. A user would not see it.

**Plan.** Each refresh works the Comms model out twice (once to decide whether to redraw, once to draw it) and the panel's sentences twice (on the check and on the draw): the next cost to cut, without changing when the panel redraws. Whether the budget should count the main thread's CPU only is a separate decision about what the bench measures.

**Where.** `plugin/hooks/panel.js` (`signature`, `comms`), `plugin/hooks/panel-stage.js`; `tools/bench-panel.mjs`.

### Real-user scenarios for four features

**What.** Four features have unit and contract tests but no real-user scenario, one that drives the real Claude Code interface the way a person does:

1. Session names and the Sessions tab: the holder named in the status line, Comms and `vbw next`, and the resume line.
2. A task break judged by the plan's own rules, on an early plan whose requirement a later plan completes.
3. A fix committing its own requirement's check files, with one approval.
4. Failing output kept and named by `vbw show fix`.

**Who and when.** Until these exist, treat the four as less proven than features that have one.

**Plan.** One scenario per feature, each checking the outcome in the record and in git, not on screen.

**Where.** `tools/l3-suite.sh` (add a `scenario_NAME` function and the name to the list); `tools/l3.sh` is the driver. Scenarios use model usage, so this needs Claude Code access.

## Under consideration

### Cost per correct outcome

**What.** VBW's benchmark so far compares cost per run on small practice cases ([benchmark.md](benchmark.md)), where VBW's up-front planning and proof cost more than a quick prompt. Cost per run is not the question a user has. Ten cheap turns that ship broken code waste more than five dearer turns that ship proven code. The idea is to measure and show VBW's cost per proven result, with the cost of rework counted on the plain side too.

**Who and when.** Everyone choosing whether VBW is worth its cost.

**Open questions.** What counts as a correct outcome on the plain side (the same checks decide)? How is rework counted? The current cases are small and have one requirement each, so they cannot answer this; it needs multi-requirement projects ([Not measured](benchmark.md#not-measured)).

**Where.** `vbw show costs` (`plugin/lib/cmd-show.sh`, `plugin/lib/costs.sh`); `tools/baseline/`.
