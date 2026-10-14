# v2

## Goals

VBW is a Claude Code plugin that makes it build software properly: the user agrees on what to build, VBW writes tests that must pass, builds the work in parallel, proves it works, and asks the user only about what tests cannot judge. It is for anyone who builds with Claude Code, from people who have never written code to senior engineers, and it adapts how it talks to each.

## Non-goals

## Constraints

## Requirements

- R1 [auto] Two consent grants made at the same time from different worktrees of one clone are both kept
- R2 [auto] A vbw command interrupted mid-commit leaves no stray index files in .vbw/runtime and keeps the caller's own exit cleanup
- R3 [auto] vbw report and vbw rtk do what their help says
- R4 [auto] In a real session, a documentation requirement is built by the Docs agent and proved
- R5 [auto] In a real session, QA fails a phase whose build deviates from its plan, and the fix loop closes it
- R8 [auto] In balanced autonomy, a background QA run causes no Stop-hook errors and the session reaches the accept stop
- R10 [auto] Blocking or resetting a plan (its note or status) never withdraws the user's approval of an unchanged contract
- R11 [auto] Accepting a [human] requirement closes only the fixes opened by the user's own rejections; a fix QA opened stays open until QA passes the phase again
- R12 [auto] QA cannot record a verdict on a proof older than the current code: vbw qa record refuses and asks for vbw prove first
- R13 [auto] While one session's VBW run is open, vbw next in another session says the run belongs to another session and to wait or check status; it never tells that session to end the run
- R14 [auto] vbw run end from a session that does not own the open run is refused, unless the user states that the owning session is closed or the run is older than 24 hours
- R15 [auto] While a run is open, another session, neither its main conversation nor its agents, can edit the files that run is writing
- R16 [auto] Turning on autonomous mode in one session leaves it on in every other session where it was on
- R17 [auto] tools/baseline holds the plan's seven benchmark cases (fix-oneshot, failing-check fix, brownfield feature, safety-destructive, safety-secret, hostile-repo, markdown deliverable), each with a deterministic pass/fail check that fails on the untouched starting project and passes on a correct solution
- R18 [auto] The benchmark has run every case 3 times with plain Claude Code and 3 times with VBW 2, on Sonnet 5.5 and on Opus 5.5, and its committed results record each run's pass or fail, tokens and cost
- R19 [human] docs/benchmark.md compares VBW 2 with plain Claude Code case by case, shows VBW 1 from its recorded runs and behaviour ledger, and states plainly what was not measured
- R20 [human] README.md presents VBW 2 to someone new: what it does and why, how to install it, a first project, the commands, with images
- R21 [auto] CONTRIBUTING.md and the repository's other contributor files describe VBW 2 only: every command, path and tool they name exists
- R22 [auto] Before planning finishes, every phase has a rigor tier (express, standard or deep) with its reasons, computed from measured signals (requirement count, planned files and size, risk paths, proven requirements it could break, test coverage), and the approval shows each phase's tier and reasons in one line
- R23 [auto] A phase whose signals call for a higher tier (a risk path such as sign-in, payments, data migrations, secrets, deletion or CI, or many requirements) is never planned below that tier: the Architect may only raise a tier, never lower it
- R24 [auto] An express phase is approved in one step (its requirement, check and plan together), built by one Dev and proved, and runs QA only when a requirement needs a person's judgement or the phase escalated
- R25 [auto] While a phase runs, VBW raises its tier on its own and records and shows why when a Dev blocks, a fix needs a second round, QA finds a problem in an express phase, the change touches a risk path or grows well beyond its plan, or a proven requirement fails; it never lowers a tier during a run
- R26 [auto] Which agents run, how many, the QA tier and the models follow each phase's tier through the profile
- R27 [auto] The tier is chosen automatically by default; the user can force it with vbw config rigor auto, express, standard or deep
- R28 [auto] Each finished phase records its predicted tier and the outcome (fix rounds, QA findings, escalations), and vbw show reports how often the prediction held; cost is measured per session by the benchmark
- R29 [auto] On the seven single-task benchmark cases, VBW 2 with automatic rigor passes every case and costs at most twice what plain Claude Code costs, on Sonnet 5.5 and Opus 5.5
- R30 [human] The benchmark adds at least three multi-requirement projects (a feature on an existing codebase with earlier requirements to protect, a data migration, and a third non-UI project of several requirements), each graded by a deterministic check, run with plain Claude Code and VBW 2, and docs/benchmark.md reports them plainly
- R31 [auto] Before approval, every [auto] requirement lists the rules its text states (each condition, edge and error case), each with the check that tests it; vbw apply refuses a listed rule that no check tests, naming it, and the approval screen shows the rules with their checks
- R32 [auto] vbw prove runs the checks and project commands on a clean copy of the committed code, so uncommitted changes and untracked files in the working folder change no proof result; vbw check keeps running on the working folder for the Dev's red and green steps
- R33 [auto] A VBW that opens a project record written by a newer VBW says the project needs a newer VBW and how to update, instead of calling the record corrupt, and every VBW still reads the records of older versions
- R34 [auto] A real-user scenario in tools/l3-suite.sh shows both in the real Claude Code app: a request that states an edge case gets a check for that edge before approval, and a leftover untracked file in the working folder does not change the proof
- R35 [auto] In every profile and rigor tier, QA agents run on Sonnet or a stronger model, never Haiku; other roles keep the models their profile gives them
- R36 [auto] vbw config set model.qa refuses a model weaker than Sonnet (haiku) and says QA needs Sonnet or stronger; sonnet, opus and default are still accepted
- R37 [auto] At the start of a project (after mapping, for existing code), VBW asks three fixed questions: how much software the user has built (never, small scripts or no-code, professionally, senior engineer), how VBW should explain things (plain words, plain with technical terms explained, technical and brief), and how involved they want to be in technical decisions (decide and tell me, options with a recommendation, I make the calls); then what they are building and for whom; then up to three follow-up questions VBW writes for that user and project
- R38 [auto] The interview's answers are kept in the project, shown by vbw status, asked only once per project (a project started before this version is asked once, at its next milestone), and can be changed later with /vbw:profile
- R39 [auto] Every VBW step that talks to the user, and every agent whose words reach the user, receives the user's level, explanation depth and involvement, and writes at that level
- R40 [auto] When VBW proposes requirements and when it presents a plan for approval, it offers at most three suggestions matched to the user's level, each one a yes or no the user may decline; an accepted one becomes a requirement or a recorded decision, and a declined one is not offered again in that project
- R41 [human] A vibe coder and a senior engineer each find VBW's wording right for their level: never too simple, never too technical
- R42 [auto] Real-user scenarios answer the interview as a newcomer and as a senior engineer; both record their answers, are not asked again, and reach the ship step
- R43 [auto] Closing a fix does not rerun a check that already passed on the same project files under the same approved contract: it says the check is unchanged since its pass, and when that pass was; vbw prove still runs every check
- R44 [auto] Several fixes close in one command (vbw fix done F8 F9 F5), running the checks their files serve once; each fix ends as it would if closed alone; a fix that cannot close is named, and the others still close
- R45 [auto] A check the contract marks to run alone (for example one that starts containers) never runs at the same time as another VBW check in the same project, even when several fixes or builds run checks in parallel
- R46 [auto] A record written by this VBW is either read by VBW 2.0.16 or makes it say the project needs a newer VBW; it is never reported as corrupt
- R47 [auto] After a round of fixes, QA checks again only the phases that did not pass and the phases whose own inputs changed since they passed (their files, their tests, or their goal and plan); an untouched phase keeps its pass
- R48 [auto] When QA runs, VBW says for each phase why it is checked again (failed last time, or which of its inputs changed) and lists the phases whose pass still stands
- R49 [auto] A phase is also checked again when a phase it builds on was checked again because its inputs changed, even if its own inputs did not
- R50 [auto] Before planning, VBW asks the user only about decisions for the milestone being planned, never about requirements of shipped milestones
- R51 [auto] A VBW panel in Claude Code shows, in plain words, the milestone and its progress, what VBW is doing right now (planning, building which parts, checking), and whether it needs the user and for what; it updates by itself within a few seconds when that changes
- R52 [auto] The panel opens by itself in a wide window, and at any width with a command; the user can close it, and it stays closed until they open it again
- R53 [auto] On Claude Code versions without mods (older than 2.1.287), or outside a VBW project, nothing breaks: no panel and no error, and the status line works as before
- R54 [human] The panel is easy to read at a glance at the user's level
- R55 [auto] The panel stays light: it uses no network, and its updates do not slow Claude Code down
- R56 [auto] The panel shows how much the current session has cost so far
- R57 [auto] VBW plays a short sound when it needs the user (an approval, a question, a result to check), picked at random from the sounds shipped with VBW in plugin/assets/audio/<character>/; one click in the panel or one command turns it off or on, and the choice is remembered
- R58 [auto] The panel shows an estimated time left for the current step and for the milestone, based on how long earlier steps took in this project, and says plainly when it has no basis for an estimate yet
- R59 [auto] The interview opens with: "Hello, Human! Welcome to VBW. Let me interview you real quick to better adapt to you. What is your level of proficiency?", with the same four options as before
- R60 [auto] At every stop, VBW ends its message with one plain line saying what it needs from the user now, or that it needs nothing
- R61 [auto] Approval is offered as a choice: VBW asks with the options Approve (first, so Enter approves), Not yet (VBW asks what to change) and the user's own words; picking Approve approves exactly the contract shown, recorded by VBW's own code from the user's answer so Claude can never approve by itself; typing /vbw:approve still works
- R62 [auto] Once the interview knows what is being built, VBW asks the user's permission to look for the best tools for this project (community skills, automated code-safety scanners, code-quality tools such as linters and formatters, unit-test and other test frameworks); on yes, Scouts research current best-in-class options for the project's stack, with sources, and VBW proposes a short list; nothing is installed until the user approves that list; on no, nothing is searched or installed; it is asked once per project, and /vbw:skills runs it again any time
- R63 [human] The recommended tools fit the project and are explained at the user's level
- R64 [auto] VBW's own real-app test sessions never play the sound aloud and never read or change the user's own panel and sound choices
- R65 [auto] When a project has a VBW 1 folder, VBW first reviews it (how much was finished, how recently it was used, whether its plans still match the current code, any work half done) and recommends converting or starting fresh with its reasons in plain words, the recommended option first; the user still chooses
- R66 [auto] Changing the plan mid-milestone (adding or changing phases) keeps each phase's QA pass; QA then checks again only new phases and phases whose own inputs changed
- R67 [auto] When a project has a VBW 1 folder and the user has not been interviewed yet, VBW opens with the interview greeting and level question, and asks convert or start fresh right after the level answer
- R68 [auto] The review of an old VBW 1 folder works on Linux as on macOS, including folders not tracked by git
- R69 [auto] vbw prove runs the approved checks in parallel, except checks marked alone, which still run by themselves; the results are the same as running them one after another, and a proof of many checks finishes in a fraction of the time
- R70 [auto] A QA round runs the project's test command once and gives its result to every QA agent of that round, instead of each agent running the whole suite again
- R71 [auto] How deeply QA checks a phase follows the size and risk of its change: a small, low-risk change gets a quick check and never a deep one, and a change to wording or documentation alone needs no new check
- R72 [auto] A small change (one or two files, low risk) goes from the user's request to done through /vbw:vibe without a planning workflow: VBW plans it itself as one plan with its check, the user approves once, it is built, checked and closed
- R73 [auto] A project's proof never reuses build output from the working folder: the clean copy has its own build folders (for any language), so artifacts never point into another copy
- R74 [auto] A plan whose files were already committed (for example by the approval commit) and whose checks pass can be marked done; a blocked or stuck plan never stops unrelated plans from being scheduled
- R75 [auto] While VBW plans, its agents may write only VBW's own files and the test files the plan declares, so a planning run never blocks another session's folders
- R76 [auto] A Dev's command that writes a file outside its plan through a program (Python, Node, Perl or similar) is refused like a shell write outside its plan
- R77 [auto] Reading the plan of record (copying or printing it) or naming the approval command in plain text is never refused as a write or as an approval
- R78 [auto] After each agent of a build, fix or QA workflow returns, VBW confirms that its plan state or verdict was recorded, and says plainly which ones were not
- R79 [auto] The test-file edits made while building a phase are approved together once, before the phase is proved, instead of one approval for each edit
- R80 [auto] One plan, check or rule can be changed without resubmitting the whole milestone, and a fix round cannot add phases or rename phases nobody asked for
- R81 [auto] A project setting limits how many checks run at the same time; an approval whose commit fails stops and says why instead of only warning; a workflow ends its own run when it finishes
- R82 [auto] The VBW panel opens at about a quarter of the terminal width (never narrower than 40 columns); a width the user sets by hand always wins
- R83 [auto] VBW always asks for approval with the approval menu, where Enter approves; it never asks the user to type /vbw:approve, which still works when the user types it
- R84 [auto] Every part of the VBW panel (the band, Mission Control, Wrapped) takes its colours from one shared palette: each agent role has one colour everywhere (architect magenta, lead blue, dev green, qa yellow, scout cyan, debugger red, docs pink), and each state has one colour (running amber, done green, failed red, quiet or cut off grey)
- R85 [auto] In Mission Control's Now tab, each agent card is framed in its role's colour and shows its state as a coloured mark and word (running, done, failed, quiet), so two agents of different roles never look the same
- R86 [auto] In the band, each agent row shows its plan label and spinner in the role's colour, its time and tokens dimmed, and the run's cost in an accent colour in the header
- R87 [auto] An agent's activity is shown as a plain intention (for example editing app-topbar.tsx, running tests, recording P6.7 done) instead of the raw command; a script run through Python, Node or another interpreter is named by what it touches; the verb is coloured and the object dimmed
- R88 [auto] When Claude Code shows a change to .vbw/record.json in the conversation, VBW shows one line saying what happened (for example VBW · build run started) instead of the full diff; the full diff still shows when the user expands the row
- R89 [auto] Mission Control's tabs stay visible at the top of the pane however long its content is, and each sentence of the pane shows its key value in colour (progress green, estimate amber, cost in the accent colour, a need of the user yellow)
- R91 [auto] When an agent starts, its new row in the band flashes briefly in its role's colour (about a second), only when the motion setting is full
- R92 [auto] The proof copy shares no writable folder with the working folder: git-ignored files and folders (dependencies, env files) are copied in, as a copy-on-write clone where the file system offers one, never linked; so a tool that refuses linked folders or writes into its dependency folders (for example pnpm 11 recursive runs and its dependency check) behaves in the proof as in the working folder, and nothing a proof does changes the working folder
- R93 [auto] After a proof, VBW checks the working folder for links that point into its proof copies and names each one with how to repair it, so damage left by an earlier VBW is found; with none, it says nothing
- R94 [auto] In one proof, a check waiting for an alone check keeps waiting as long as that check is still running; a proof never aborts because a check waited: a check that cannot run is reported as not run with the reason, every other result stands, and the proof prints no shell job warnings
- R95 [auto] Every agent of a VBW workflow (build, fix, QA, planning) records its own result through VBW (a plan's state, a fix's state, a phase's verdict) even though Claude Code marks a workflow's task text as not coming from the user; in the real Claude Code app a workflow ends with every result recorded and nothing recorded by hand, and the project's test command is named in what QA is told
- R96 [auto] A workflow's closing step (confirm what its agents recorded, then end the run) is done by an agent whose own instructions allow it; it never refuses, and when it cannot finish it says which command to run by hand
- R97 [auto] Choosing Approve in the approval menu approves the contract it names whatever text, spaces or line breaks follow the fingerprint in the question
- R98 [auto] In an autonomous run, while this session's proof or workflow is still running in the background, the stop hook does not ask for that step again and spends no autonomous step on it
- R99 [auto] A fix for a failing project command can commit the files it changed to make that command pass, even when no plan lists them, and the commit names the fix
- R100 [auto] After the plan changes (a new plan, a changed plan or a re-plan), VBW asks for approval only with the approval menu; it never tells the user to type /vbw:approve
- R101 [auto] In the balanced profile the Architect runs on Opus; QA is never below Sonnet in any profile
- R102 [auto] Planning splits each phase into plans that touch separate files wherever the work allows, so as many plans as possible build at the same time; the approval shows the number of build waves and how many plans the widest wave runs at once
- R103 [auto] When the committed project files are identical to those of the last passing proof (only VBW's own record or spec changed), vbw prove reuses that proof's results for every check and command whose approved definition is unchanged, says so, and runs only the rest
- R104 [auto] A phase is not checked by QA again when the only change since its pass is a recorded decision, a closed finding with no code change, or a removed requirement that only a person judges; a phase whose code, tests, goal or remaining requirements changed is still checked again
- R105 [auto] A phase's rigor tier is not raised by proven requirements it could affect when each of them is guarded by an approved check the proof re-runs; only proven requirements no check guards raise it, and the tier's reasons still list what the phase could affect
- R106 [auto] The Architect is given the next free phase number and proposes phases numbered from it, so planning never needs a renumbering round
- R107 [auto] Each workflow agent runs at the effort its step needs, set per role and step by the profile (lower for closing a run and for documentation, higher for planning and QA), through Claude Code's per-agent effort setting; on a Claude Code without that setting, agents run as before
- R109 [auto] vbw init's notice about detected commands names the approval menu, never the typed /vbw:approve command
- R110 [auto] vbw prove re-runs only the approved checks whose served files (the check's own files and the files of the plans serving its requirement) changed since their last pass, every check that declares no files, and every check whose definition changed; it reuses every other result and says so
- R111 [auto] A project may name a fast variant of its test command for build and fix rounds; vbw prove --full runs every check and the full project commands, and vbw qa record and vbw ship refuse a proof that ran only part of them, saying to run vbw prove --full
- R112 [auto] The interview skill says it runs before any spec or convert work, as the router does
- R113 [auto] VBW's own files under .vbw/ (the spec, the record) never make QA check a passed phase again, even when a plan lists one of them; a change to the phase's other files still does
- R114 [auto] When Claude asks the approval menu (options Approve and Not yet) without the contract's fingerprint while a contract waits for approval, VBW puts 'Approve contract <fingerprint>?' in front of the question, so the user's Approve approves exactly that contract; other questions, subagents' questions, a question that already names a fingerprint and an approved contract are left as they are
- R115 [auto] A passed phase is not checked by QA again when the only files that changed since its pass are documentation (Markdown and other docs) or recorded test results; a change to its code, its tests or its goal still lists it again
- R116 [auto] A request that names one or two files and no risk path is offered the small-change path (one phase at the tier `vbw next` names, express when its signals allow, one plan and its check, approved once) before any planning workflow starts; a larger or riskier request still goes to planning
- R118 [auto] When a check or project command fails, the proof keeps its full output in the project's runtime folder, and vbw show fix names that file, so the failing test can be read without running everything again
- R119 [auto] In the balanced profile the Lead also runs on Opus, and every role other than the Architect and the Lead runs on Sonnet
- R120 [auto] When the approval hook puts "Approve contract <fingerprint>?" in front of a reworded approval question, the user is still shown the menu and answers it: the hook asks (permissionDecision ask), it never answers the question itself
- R121 [auto] Every new request brought to /vbw:vibe gets a one-line triage before any planning: now (it joins the active milestone), next or later (it goes into the backlog with vbw todo), with the reason and a size (small, medium or large); the user confirms or overrides it in the same menu, and the outcome is recorded
- R122 [auto] When the user overrides VBW's triage, VBW says once, plainly, what the idea displaces and its risk, then follows the user's choice and records it as a decision with the user's reason
- R123 [auto] After vbw ship, and whenever the user asks, the Architect writes a what's-next recommendation from the record (open milestones and requirements, the backlog, decisions): a top pick with its reason and up to two runners-up, each with a size; the kernel stores it, and vbw status shows it
- R124 [auto] The panel's Now tab shows a What's next section with the stored recommendation (top pick and reason, up to two runners-up with sizes) and a Suggest next button that puts the refresh request in the prompt without sending it
- R125 [human] The What's next section's colour candy is subtle and elegant: a slow shimmer on its title and a soft pulse on the top pick when a new recommendation arrives, settling afterwards
- R126 [auto] CI runs its actions on their Node 24 majors, and the Linux tests also run on the Ubuntu 26 image, before ubuntu-latest moves on 2026-10-19
- R127 [auto] vbw todo sort ID next|later small|medium|large sets the sort and size of an open backlog item, which then lists with them; an unknown or closed item, or a value outside those, is refused and nothing changes
- R128 [auto] Every decision a VBW hook returns to Claude Code (permission decisions, blocking, added context, rewritten input) has a test that pins its documented Claude Code meaning, and no hook answers a question or allows an action in the user's place
- R129 [auto] vbw plan block refuses a plan that is done, with a message that says so, and nothing changes
- R130 [auto] The full vbw apply refuses a requirement that another milestone owns or already covers, as vbw apply --add does, and nothing changes
- R131 [auto] The QA prompt names the project's test command and the end of its output; when the round does not carry them, the prompt says so in plain words and never prints undefined
- R132 [auto] The QA files fingerprint carries a version, so a VBW update that changes how it is computed does not by itself send a passed phase back to QA
- R133 [auto] The what's-next reply format refuses an empty source for a pick, so one empty source can never make the kernel refuse the whole recommendation
- R134 [auto] docs/workflows.md lists every workflow in plugin/workflows (vbw:tooling included) with the right count, and docs/proof.md says a Test results folder name cannot contain spaces
- R135 [auto] The router's triage line reads as a correct sentence whatever the user typed after /vbw:vibe, including nothing
- R141 [auto] When jq is missing, starting a Claude Code session in a VBW project shows no 'jq: command not found' error: the session-start hook ends quietly like the other hooks
- R142 [auto] CI splits the macOS test run across several machines, so a push that changes VBW code finishes CI in about 20 minutes or less
- R143 [auto] When a push changes no shipped code, tools or docs, CI runs only the test files that changed, and skips the tests when only the VBW record or saved test results changed
- R144 [auto] When a fix after QA changes only documentation, the next full proof reuses the project test command's earlier passing result instead of running it again; any change to code, tests or a check's files still runs it
- R145 [auto] A phase that was escalated (raised after a blocked plan, a failed fix or a failed QA) is verified at the QA depth of its raised tier; the small-change discount applies only to phases that never escalated
- R146 [auto] vbw todo add, sort, done and drop commit the record when they change it, so the project is left clean, and never take the user's own staged files with them
- R147 [auto] By default VBW runs at most as many checks at once as the machine can carry (about three quarters of its processor cores, at least one), instead of 4 on every machine; the check_jobs setting still overrides it
- R148 [auto] When several Devs or fix groups work at once, the checks they run together stay within that same machine-sized limit, and fix groups share one run of the project test command instead of each running it
- R149 [auto] Every vbw command works on a project whose record (.vbw/record.json) is larger than the operating system's command-line limit (over 1 MB, as long-lived projects reach): no record-sized data is ever passed to a helper program as a command-line argument
- R150 [auto] A guard's cost per tool call stays within its budget however long the record grows: every record that has checks keeps the protected check files as one short list near its top (record format 4), and the guards read only that list, never the checks themselves; there is one way to read it, with no size threshold
- R151 [auto] VBW's speed checks fail only on a real slowdown: a hook's own cost above 20 ms per call, or the status line above 60 ms; when the machine is too busy to measure (starting the shell and jq alone takes longer than the hook limit) the check reports the machine as busy and does not fail
- R152 [auto] The timed speed checks run once per release (in CI and in the local run before a push), not in every vbw prove, so a proof never fails or waits because the machine is busy
- R153 [auto] vbw prove never stops a project's test command only because the machine is busy: its time limit fits a large project's full test run on a loaded machine, and a project can set its own limit
- R154 [auto] vbw config rigor works under macOS /bin/bash 3.2: setting a mode re-tiers the unstarted phases and saves the record, as it does under bash 5
- R155 [auto] VBW's own test suite passes under macOS /bin/bash 3.2: a test that edits the record by hand also drops the status line's side file, as a kernel write would refresh it
- R156 [auto] A milestone can re-plan a requirement it reopened from a shipped milestone: a full vbw apply accepts phases that cover it, and every vbw apply refusal names the mode it came from (full apply, --add or --patch)
- R157 [auto] A re-plan can add a new phase for more work on a requirement that a started phase already covers; the started phase and its finished plans stay exactly as they are
- R158 [auto] A re-plan can change the goal and criteria of a phase that has not started
- R159 [auto] A re-plan never raises the tier of a phase that has started or finished; the minimum rigor is judged for unstarted phases only
- R160 [auto] A fix that follows a QA finding can add its regression test: the fix run may create new test files, registered as checks of the finding's requirement, and edits to an approved check file wait for one approval by the user before the proof
- R161 [auto] A [human] requirement the user wants to judge later can move to the next milestone, keeping its id, its checks and its history
- R162 [auto] Every refusal VBW gives while a plan changes (vbw apply, vbw run start, the guards) says what to do instead
- R163 [auto] --help or -h on any vbw command prints that command's usage and changes nothing (no record write, no commit)
- R164 [auto] Before a push, the release run adds only the timed speed checks and the benchmarks when a passing full proof already covers the same code (only version files and the changelog changed since); otherwise it runs everything
- R165 [auto] During a VBW run, a VBW guard that crashes, cannot start or times out blocks the action it guards instead of letting it through; outside VBW projects and outside runs nothing changes
- R166 [auto] Every proof, including the full proof that QA and shipping require, re-runs only the checks a change can affect and reuses the passing result of every other check; a check is affected when a file it lists or a project file it reads has changed since its last pass
- R167 [auto] The project's test command re-runs only the test files a change can affect when the project's test runner can run single test files; otherwise it runs whole; a one-file fix in VBW itself proves in minutes, not the whole suite
- R168 [auto] When VBW cannot know what a change reaches, the proof runs everything and says why: the file system records no reads, this clone has no recorded run, the last proof was cut short, nothing was committed since the last passing proof, or a file was added or deleted that no recorded run read or listed the folder of; a changed approved command, single-file form or list of test files re-runs only what runs through it; the proof summary says how many checks and test files ran and how many were reused
- R169 [auto] When the declared test-file form leaves no file to run as a unit of its own (every file it matches already runs as an approved check), the proof records no nameless unit, counts the test command as covered by those checks, and says so; when the form matches no tracked file at all, the proof fails the test command and names the form
- R170 [auto] Before a push, the release run reuses the last proof when it passed, left no command skipped and no quick command standing in, and only the version files and the changelog changed since, whether or not it reused earlier results (a reused result is one the read lists still vouch for); it then runs only the benchmarks and the timed speed checks; otherwise it runs everything and says why
- R171 [auto] While the contract cannot be approved yet (a check file is missing, the spec and the record differ), vbw next does not offer the approval question: it says the contract is not ready, names each problem and the step that fixes it, so the user is never asked to approve a contract that approval would refuse
- R172 [auto] The test helper leaves the repository before its git calls and turns off background git work (garbage collection, maintenance), and the test that checks this runs the helper in a plain shell, never a bats run inside a bats run, so the suite gives the same result on macOS bash 3.2 and on Linux bash 5
- R173 [auto] VBW records what each run and each milestone cost in tokens and money, from the facts Claude Code provides, so the kernel can read the totals per run and per milestone and compare them with a ceiling
- R174 [auto] vbw approve compares every section of the spec with the record, the Test results list included, so an edited list that was not synced cannot be approved as the record's list
- R175 [auto] The proof's cause "nothing was committed since the last passing proof" fires only when the project's code is the code that proof proved (its recorded tree), never from the subject of the last commit, so a record commit landing after other commits does not re-run everything
- R176 [auto] vbw fix done prints what it ran and what it reused, checks and test files, with the counts the proof summary prints, and saves the test files it ran in the run store so the next proof reuses them
- R177 [auto] During a run, VBW's guards deny any write by an agent to a path outside the project folder (a file write or a shell redirect, /tmp included), saying where the run may write instead; outside runs and outside VBW projects nothing changes
- R178 [auto] With vbw loop start ITEM... --ceiling USD the user delegates approval to the loop for the named backlog items: a contract whose requirements are exactly those items (their recorded text, nothing more) is approved by the kernel without a question, recorded as approved by the loop on the user's behalf; any other contract still waits for the user
- R179 [auto] /vbw:loop runs the unattended cycle for the loop's items in order (milestone, plan, approve by delegation, build, prove, fix, QA, ship): an escalated fix is retried once, then its item is parked with the reason and the loop moves to the next item; a [human] requirement is skipped for the user to judge later; the loop stops at the cost ceiling, at the end of its list, or when the user runs vbw loop stop from any session, and leaves .vbw/loop-report.md saying what shipped, what was parked and why, and what it cost
- R180 [auto] The loop never pushes, releases or publishes: nothing it does leaves the project, every ship stays local for the user's review, and the guards that hold for any run hold for the loop's runs
- R181 [auto] Machine-wide limit (owner, 2026-10-12 09:40): VBW as a whole never takes more than about three quarters of the machine's cores, however many projects, sessions and runs are proving at once: one shared budget per machine (a slot store in the user's Claude config folder, each unit of a proof or fix done takes a slot, a run that finds none waits its turn), so runs take turns instead of fighting (today a 12-minute fix done took 87 under four concurrent runs). Same tests, same results, no thrash; the check_jobs setting stays as a per-run cap below it. Goes with T127 (one fix done per fix round). First item after 2.0.34, before the loop
- R182 [auto] Several vbw fix done runs at once slow each other down (2026-10-12: three in parallel plus another session's run took a 12-minute run to 87 minutes). The fixing workflow has every Dev run its own fix done, so a round with several groups already runs several at once. Decide: the kernel serialises fix done runs (one proof lock per clone, the later ones wait and reuse), or the workflow runs one fix done for all groups at the end; measure first
- R183 [auto] Stale proof copies: a process killed outright leaves its .vbw/runtime/proof.* copy (13 MB seen 2026-10-12 05:26 from a killed duplicate fix done); the next proof removes copies whose owner process is gone (record the owner pid in the copy folder, as the gate's mutex does), with a test. Part of the machine-wide limit milestone (T128)
- R184 [auto] A project where the VBW plugin is disabled shows no VBW (owner, 2026-10-12 12:30, Portfolium-webstack): the status line VBW installs is a user-level setting that runs in every project, so it keeps showing after a per-project disable (enabledPlugins false in the project's .claude/settings.json; Claude Code itself reports the plugin disabled there). The status line script checks the project's settings and prints nothing (or the previous status line) where the plugin is disabled; the same for the panel if it turns out to persist. Part of the machine-wide-limit milestone or its own small one
- R185 [auto] The session must run the loaded plugin's kernel (2026-10-13 14:54): in the v2 worktree the vbw on PATH was the installed release (2.0.34), put there by the SessionStart hook, so every kernel command of the session ran the released code and the record became unreadable to it once an agent wrote a new field through plugin/bin/vbw; with claude --plugin-dir ./plugin the loaded plugin's bin must be the one on PATH and the status line must show the loaded version (replaces T54: --plugin-dir did not override the installed copy); document the local-dev path

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->

## Commands

- test: bash tools/test.sh
- quick: bash tools/test.sh --quick
- lint: bash tools/test.sh --lint

## Test files

- run: bats --print-output-on-failure {file}
- files: tests/*.bats :!tests/timed-*.bats

## Test results

- tools/l3-results/
- tools/baseline/results/
