# Known issues and roadmap

What is known to be wrong or unfinished in VBW 2.1.0, what is planned, and what is still only an idea. Larger open ideas that need design work are in [ideas.md](ideas.md).

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
| [Mission Control may not open at session start](#mission-control-may-not-open-at-session-start) | Known issue | Wide windows | `/vbw-panel` |
| [The loop's time budget follows the size label](#the-loops-time-budget-follows-the-size-label) | Known issue | Loops | Re-run the item |
| [Approved rules cannot be reworded or retired](#approved-rules-cannot-be-reworded-or-retired) | Known issue | Re-planning | None clean |
| [Time estimates absorb idle time](#time-estimates-absorb-idle-time) | Known issue | Estimates | Delete `steps.json` |
| [Heavy checks each use every core](#heavy-checks-each-use-every-core) | Known issue | Cargo, make, similar | Lower `check_jobs` |
| [Two proofs at once are much slower than one](#two-proofs-at-once-are-much-slower-than-one) | Known issue | Parallel sessions | Prove one at a time |
| [Slot store edge cases](#slot-store-edge-cases) | Known issue | Sandboxes, many runs | None needed |
| [Status line speed where VBW is off](#status-line-speed-where-vbw-is-off) | Planned | Slower Macs | None needed |
| [Panel drawing headroom](#panel-drawing-headroom) | Planned | Slower Macs | None needed |
| [Panel polish](#panel-polish) | Planned | Everyone | None needed |
| [Real-user scenarios for four features](#real-user-scenarios-for-four-features) | Planned | Test coverage | Not applicable |
| [A test that orders events by wall clock](#a-test-that-orders-events-by-wall-clock) | Planned | Contributors | Not applicable |
| [Cost per correct outcome](#cost-per-correct-outcome) | Idea | Everyone | Not applicable |

## Known issues

### Mission Control may not open at session start

**What.** In a wide window, Mission Control (the pane beside the conversation) is meant to open by itself when a session starts in a VBW project ([panel.md](panel.md#open-and-close-it)). It was seen not to: the pane stayed closed until a VBW run started.

**Who and when.** Seen once, on an early 2.0 build loaded with `claude --plugin-dir`, in a wide window. We have not found the cause and have not established whether an installed copy is affected.

**Workaround.** `/vbw-panel` opens the pane at any width.

**Plan.** Find the gap in the launch trigger, fix it, and add the case to the panel's real-user scenario.

**Where.** `plugin/hooks/panel.js` (the `session.start` handler and the open request); `tools/l3-suite.sh` (the `panel` scenario).

### The loop's time budget follows the size label

**What.** When the loop opens an item, its time budget is twice the median time of shipped items with the same size label, or 2, 4 or 8 hours for small, medium and large when there is no history ([loop.md](loop.md#the-time-budget)). The label is a guess made before planning. An item labelled small that turned out to be eleven plans in three phases was stopped at the small-item budget. Time lost to dropped network connections or to waiting for you counts as time, so it can also stop a healthy item.

**Who and when.** Anyone running `/vbw:loop` over a backlog with items whose size was guessed wrong.

**Workaround.** The stop keeps all the work and parks nothing. Run `/vbw:loop THE_ITEM` again, or finish the item with `/vbw:vibe`. Give items an honest size (`vbw todo add --size`, `vbw todo sort`).

**Plan.** Once an item is planned, its budget becomes twice the kernel's estimate of its road ([panel.md](panel.md#time-left)). The stuck test counts progress (plans done, fixes closed), so waiting is not grinding. Before planning, the size default stays.

**Where.** `plugin/lib/loop-step.sh` (`loop_item_budget`); the estimate comes from `plugin/lib/road.jq`.

### Approved rules cannot be reworded or retired

**What.** A rule is one approved condition of a requirement, tied to a check. `vbw apply --patch` matches a rule by requirement and text ([workflows.md](workflows.md#changing-one-thing-vbw-apply---patch)), so new wording adds a second rule and the stale one stays. A rule of a shipped milestone cannot be reached at all. When a later requirement changes behaviour, the earlier rule is left standing and can contradict the new one.

**Who and when.** Projects that change the behaviour a shipped requirement described. It shows up when the Lead re-plans.

**Workaround.** None that retires the stale rule. Adding the new rule beside it keeps both checks running.

**Plan.** Give rules a stable address that a patch can reword or retire, with a new approval. A kernel step is needed to supersede a rule of a shipped requirement.

**Where.** `plugin/lib/cmd-apply.sh`; the record's `rules` ([record.md](record.md)).

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

### Two proofs at once are much slower than one

**What.** In one measurement, two proofs started together on one computer took 335 seconds together; one proof alone took 57.6. The shared limit was 7 slots and all 7 were held at the peak. Run one after the other, the two would take about 115 seconds, so the shared run took about three times as long.

**Who and when.** People who run two sessions, or two projects, that prove at the same time.

**Workaround.** Prove one project at a time on a machine when you can.

**Status.** Cause not found. The leads, none tested: contention on the slot store's lock; waiting units polling the store every 0.1 s with several `jq` runs per poll; the heavy-check overload above.

**Plan.** Find the cause and fix it. `tools/measure-proof-speed.sh` is the starting point for a measurement.

**Where.** `plugin/lib/slots.sh`, `plugin/lib/checks.sh`.

### Slot store edge cases

**What.** The computer-wide limit is kept in a small shared store (`slots.json` in the Claude config folder, [proof.md](proof.md#the-computer-wide-limit)). Three weaknesses remain, none breaking a requirement:

1. Two runs that find the same dead lock owner can both delete the lock and briefly allow one slot too many. The fix is to take the lock over with an atomic rename.
2. When the lock cannot be created but the folder looks writable (a sandbox, a full disk), the first step retries for about 30 seconds before saying it cannot write. It should detect this at once.
3. Smaller: `vbw plan done` may print the "limit was not in force" line twice on an unwritable store and never prints the end-of-run waited line; a waiting entry left by a unit that lost the store stays until its run exits.

**Who and when.** Sandboxed sessions, full disks, and many runs at once. The effect is a pause or one extra check at a time, never a wrong result.

**Workaround.** None needed. `check_jobs` still applies.

**Plan.** A test for each case, then the fixes.

**Where.** `plugin/lib/slots.sh` (`slots_lock`, `slots_open`).

## Planned improvements

### Status line speed where VBW is off

**What.** In a project where VBW is turned off, the status line hands back to your earlier status line ([statusline.md](statusline.md#projects-where-vbw-is-turned-off)). That path is the slowest of the status line's paths. It measured 60.2 ms on GitHub's macOS runner against a 60 ms budget, and 42 ms on a developer Mac.

**Who and when.** Slower Macs, in projects where VBW is off. Nothing breaks; the line may take a little longer to draw. Our own release benchmark can also fail on a slow runner.

**Plan.** Make the path cheaper, or judge CI against a calibrated budget the way the panel benchmark already does (`VBW_PANEL_BUDGET_MS`).

**Where.** `plugin/scripts/vbw-statusline.sh`; `tools/bench-hooks.sh` (the `status line (VBW off)` line).

### Panel drawing headroom

**What.** Drawing Comms and Mission Control together costs 0.47 to 0.51 ms of CPU against a 0.5 ms budget, since the tab layout moved to whole rows. The layout measures the head once per candidate; it only needs to once per width.

**Who and when.** A slower Mac could fail the release benchmark. A user would not see it.

**Plan.** Profile the render path and win the headroom back. The figures in [panel.md](panel.md#what-it-reads-and-what-it-costs) should then be re-measured.

**Where.** `plugin/hooks/panel-pane.js` (`layout`); `tools/bench-panel.sh`.

### Panel polish

**What.** A last visual pass on Comms and Mission Control: tidier spacing, a one-line "work is running" animation in place of the larger figure, and a time (`HH:MM`) on more of the panel's short messages.

**Who and when.** Everyone who uses the panel. Nothing depends on it.

**Plan.** Done by eye, so the exact list may change.

**Where.** `plugin/hooks/panel-pane.js`, `plugin/hooks/panel-lines.js`, `plugin/hooks/panel-candy.js`.

### Real-user scenarios for four features

**What.** Four features have unit and contract tests but no real-user scenario, one that drives the real Claude Code interface the way a person does:

1. Session names and the Sessions tab: the holder named in the status line, Comms and `vbw next`, and the resume line.
2. A task break judged by the plan's own rules, on an early plan whose requirement a later plan completes.
3. A fix committing its own requirement's check files, with one approval.
4. Failing output kept and named by `vbw show fix`.

**Who and when.** Until these exist, treat the four as less proven than features that have one.

**Plan.** One scenario per feature, each checking the outcome in the record and in git, not on screen.

**Where.** `tools/l3-suite.sh` (add a `scenario_NAME` function and the name to the list); `tools/l3.sh` is the driver. Scenarios use model usage, so this needs Claude Code access.

### A test that orders events by wall clock

**What.** `tests/machine-bookkeeping.bats` orders events by the wall clock in whole seconds, and is exempted as a whole from the rule that keeps timing out of the default test run. Two events in the same second cannot be told apart.

**Who and when.** Contributors. The risk is an unreliable test.

**Plan.** Order the events by a sequence number and drop the exemption.

**Where.** `tests/machine-bookkeeping.bats`; the exemption is in `tests/release-run.bats`.

## Under consideration

### Cost per correct outcome

**What.** VBW's benchmark compares cost per run ([benchmark.md](benchmark.md)), and VBW 2 costs several times plain Claude Code per run on small cases. Cost per run is not the question a user has. Ten cheap turns that ship broken code waste more than five dearer turns that ship proven code. The idea is to measure and show VBW's cost per proven result, with the cost of rework counted on the plain side too.

**Who and when.** Everyone choosing whether VBW is worth its cost.

**Open questions.** What counts as a correct outcome on the plain side (the same checks decide)? How is rework counted? The current cases are small and have one requirement each, so they cannot answer this; it needs multi-requirement projects ([Not measured](benchmark.md#not-measured)).

**Where.** `vbw show costs` (`plugin/lib/cmd-show.sh`, `plugin/lib/costs.sh`); `tools/baseline/`.
