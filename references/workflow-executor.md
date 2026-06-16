# Workflow Executor Backend

VBW can optionally offload **wide, parallel, bounded** steps to a [Claude Dynamic
Workflow](https://code.claude.com/docs/en/workflows) instead of running its own
Agent-Team/subagent fan-out. This is an **optional capability**, gated by the
`prefer_workflows` config setting and detected at runtime — exactly like LSP, MCP,
and `prefer_teams`. `prefer_workflows` is evaluated **before** `prefer_teams`: a
workflow is the preferred parallel backend, with Agent Teams as the fallback. When the runtime does not support workflows, or the user opts
out, VBW behaves **identically to today**.

A Claude Dynamic Workflow is a JavaScript script the Claude Code runtime writes
and executes in the background, orchestrating many subagents at scale; the script
holds the loop, branching, and intermediate results, and only the final answer
returns to the session. "The script holds the plan."

Per the [official docs](https://code.claude.com/docs/en/workflows), workflows are
a **research preview** requiring Claude Code **v2.1.154+**. They are available on
all paid plans, but on **Pro they are opt-in** (enabled from the Dynamic workflows
row in `/config`). Detection from a shell script cannot see the running CLI
version or the Pro opt-in state, so `detect-workflows-support.sh` reports only the
strongest disk/env signal (workflows not explicitly disabled). The runtime is the
final authority: a step VBW dispatches as a workflow may still be refused at
invocation, so the orchestrator's graceful fallback on refusal — not detection —
is the primary backward-compat safety net.

## Division of responsibility (composition, not replacement)

VBW remains the **lifecycle owner**. A workflow is only ever an *executor for one
step* — never the owner of phases, plans, gates, verification, or cross-session
resume.

| Concern | Owner |
| :--- | :--- |
| Phase/plan state, routing, gates, QA→remediation, resume | VBW (`phase-detect.sh`, `control-plane.sh`, disk artifacts) |
| Deciding a step is wide enough to offload | VBW (`resolve-executor.sh`) |
| Running the fan-out for that one step | Workflow runtime (when selected) |
| Persisting the step's result into durable state | VBW (result-bridging, below) |

This composition is deliberate: VBW's value is durable, inspectable, verifiable,
cross-session-resumable state as the source of truth, while workflows are
ephemeral (resumable only within a session) and keep their intermediate results
out of context. Folding the VBW lifecycle into a single workflow would forfeit
all of that, so we do not.

## When a step qualifies

A step is workflow-eligible when it is:

- **Wide** — fans out across many independent units (files, modules, endpoints,
  targets) beyond the configured threshold.
- **Parallel** — the units have no ordering dependency on each other.
- **Bounded** — the unit set is enumerable up front and each unit's work is
  self-contained.

Good fits: large codebase audits/scans, multi-target verification, mechanical
migrations applied across many files. Poor fits: ordered plan execution, anything
requiring VBW gates/QA between units, or single-unit work.

## Decision pipeline

1. **Config** — `scripts/normalize-workflows-mode.sh` canonicalizes the
   `prefer_workflows` setting to `always | auto | never`.
2. **Detection** — `scripts/detect-workflows-support.sh` reports whether the
   runtime supports workflows (honors `CLAUDE_CODE_DISABLE_WORKFLOWS` and
   `disableWorkflows` in merged settings). Fails **closed** (unsupported) when it
   cannot confirm support.
3. **Resolution** — `scripts/resolve-executor.sh --fanout <N>`
   returns `workflow` or `fallback`:
   - `never` → `fallback`
   - runtime unsupported → `fallback`
   - fanout below minimum (`< 2`) / non-integer → `fallback`
   - `always`, fanout ≥ 2 → `workflow`
   - `auto`, fanout ≥ 2 → `workflow` (mirrors `prefer_teams=auto`; both require real parallel work)
4. **Dispatch** — on `workflow`, the orchestrator runs the step as a workflow and
   records `delegation_mode=workflow` in `.delegated-workflow.json`. On
   `fallback`, the orchestrator runs its **existing** team/subagent/direct
   resolution (e.g. `resolve-execute-delegation-mode.sh`) unchanged.

`resolve-executor.sh` is an orthogonal predicate — it answers only "workflow or
not." It never re-implements team/subagent/direct selection.

On Execute specifically, this orthogonality means `prefer_teams` does **not** gate
the workflow. A parallel delegate wave (segment `plan_ids` length ≥ 2) is offered
to `resolve-executor.sh` whether the resolver labeled it `team`
(`prefer_teams=always`, or `auto` with parallel width) **or** `subagent`
(`prefer_teams=never` — the resolver still keeps the wave grouped). When the
executor returns `workflow`, it is the **preferred** parallel backend over Agent
Teams; when it returns `fallback`, `prefer_teams` selects the fallback as before
(team vs. serialized subagent). See `execute-protocol.md` "Workflow executor
evaluation".

## Model and effort governance

**Workflow workers are governed by VBW's per-agent model/effort resolution — they do
NOT inherit the session's model or any `ultracode` escalation.** This is a core VBW
invariant: model and effort are chosen *per agent role* via `resolve-agent-model.sh`
/ `resolve-agent-settings.sh` against `model-profiles.json` (plus the user's
`model_overrides`), not turned up globally. A workflow is just another executor for
one step, so its workers obey the same governance:

- The orchestrator resolves the worker's model the same way it would for a
  `Task`/team subagent of that role (for the map path: `scout`, which the default
  `quality` profile resolves to **Sonnet**, `budget` to **Haiku** — never Opus
  unless a user override insists), and passes it explicitly via
  `agent(prompt, { agentType: 'vbw:vbw-scout', model })`.
- VBW escalates to a frontier model / full effort **only** when the user has
  customized their per-agent models (`model_overrides` or a custom profile) to
  demand it. Absent that, VBW's learned per-agent defaults win — even inside a
  workflow.
- The `ultracode` keyword path cannot honor this (no `{ model }` lever, and it forces
  xhigh + frontier), which is why it is a *degraded* alternate, not a peer of the
  direct tool.

### Cost anchor

One real data point shows why this matters. A live Opus 4.8 run on a 4,614-file
monorepo (4× `vbw:vbw-scout` via `parallel()`) where workers **inherited** the
session Opus model rather than being governed:

| Metric | Value |
| :--- | :--- |
| Repo size | 4,614 source files (monorepo, 6 submodules) |
| Executor | 4× `vbw:vbw-scout` |
| Wall-clock | ~194 s |
| Tool uses (all agents) | 72 |
| Subagent tokens | ~300k (workers **inherited** Opus — the anti-pattern) |
| Output | all 7 codebase docs written |

~300k tokens for a 4-wide Opus scan is the cost of letting workers inherit the
session model. Under governance the same map resolves `scout` to Sonnet (Haiku on
`budget`), cutting that spend substantially; CMM-vs-raw navigation behavior is
largely model-independent, so the governed default loses little for routine maps.
The `auto` fan-out threshold (`resolve-executor.sh --threshold`, default 25) is the
separate lever for *whether* to fan out at all; a quad-tier repo clears any sane
threshold, so on a large repo `auto` will select the workflow once the runtime
supports it.

### Worker-count cap (`workflow_max_workers`)

The runtime enforces hard ceilings — **up to 16 concurrent agents and 1,000 total
per run** ("Behavior and limits", official docs) — and exposes no setting to lower
them. VBW cannot raise those ceilings, but since it authors the script it
dispatches, it can hold the fan-out below them. The `workflow_max_workers` config
(integer, default `4`, `0` = no VBW cap) is that bound: when authoring a workflow
script, the orchestrator caps the `parallel()` / `pipeline()` fan-out width — and
batches wider work — to at most this many concurrent workers. Resolve it with
`normalize-workflow-max-workers.sh`. This is orthogonal to `prefer_workflows`
(workflow-or-not) and to model governance (which model each worker runs); it
governs only how many run at once. The default `4` matches the `/vbw:map` quad
scan's four domains; raise it for wider audit/migration steps, lower it to throttle
cost.

## Invoking a workflow

The orchestrator has three ways to run a qualifying step, in priority order. All
three are gated by the same `detect-workflows-support.sh` signal — when detection
reports unsupported, the orchestrator skips straight to the fallback.

**1. The `Workflow` tool (primary).** When the runtime exposes a first-class
`Workflow` tool, the orchestrator calls it directly with an inline JS script —
`Workflow({ script })` — and the script body fans out to workers via
`agent(prompt, { agentType: 'vbw:vbw-scout' })`. This is deterministic and
orchestrator-initiated: no reliance on Claude choosing to author a workflow from
a typed keyword. The script may also pass `{ schema }` (forces a validated
structured return), `{ label }`, `{ phase }`, `{ model }`, and
`{ isolation: 'worktree' }` per worker. **Crucially, the per-worker `{ model }`
option lets VBW assign each worker the model its normal per-agent governance
resolves** (`resolve-agent-model.sh` / `model-profiles.json` + effort +
`model_overrides`) instead of letting workers inherit the session's
(possibly escalated) model — this is the main reason the tool is preferred over the
keyword (see "Model and effort governance" above). `detect-workflows-support.sh`
gates this direct-tool path exactly as it gates the keyword path; the runtime
remains the final authority and may still refuse, in which case the orchestrator
falls back. Confirmed empirically (Opus 4.8 runtime) — see
`workflow-executor-empirical-notes.md`.

**2. The per-request `ultracode` keyword (degraded alternate).** Where the direct
tool is unavailable but the keyword is, the orchestrator emits the per-request
`ultracode` keyword in the dispatched request (e.g. `ultracode: <step task>`) to
generate an ephemeral workflow for that one request. **This path forfeits VBW's
per-worker model governance:** `ultracode` escalates reasoning to xhigh and pushes
frontier models, and the keyword gives VBW no `{ model }` lever to pin workers to
their resolved per-agent model. Use it only when the direct tool is absent, and
accept that workers run hotter/more expensive than VBW would otherwise choose (see
"Model and effort governance" below).

**3. The Scout team / subagent path (fallback).** When neither workflow surface
is available (or the runtime refuses at invocation), the orchestrator runs its
existing team/subagent/direct delegation unchanged.

Workflows run in the background; `/workflows` lists running and completed runs.
Resume is within-session only — the tool exposes
`Workflow({ scriptPath, resumeFromRunId })` to resume an interrupted run *within
the same session* (completed agents return from cache). Cross-session resume is
not available: if the session exits mid-run, the next session starts the step
fresh, so VBW must treat an unfinished workflow step as not-yet-done and
re-dispatch on resume.

**VBW uses only the per-request keyword — never `/effort ultracode`.** The docs
expose `ultracode` in two forms: the per-prompt keyword (writes one workflow for
that request) and the `/effort ultracode` mode (xhigh reasoning plus *automatic*
workflow orchestration for every substantive task). The effort mode would make
Claude spawn workflows on its own for every task, colliding with VBW's
deterministic, single-step, opt-in dispatch. VBW must keep the trigger explicit
and per-step. The direct `Workflow` tool is the clean per-step trigger and avoids
this collision entirely — it is invoked explicitly, once, per qualifying step.
Beyond the auto-spawn collision, **`ultracode` in either form turns reasoning to
xhigh and pushes frontier models for every agent it touches**, which directly
contradicts VBW's per-agent model/effort governance (see "Model and effort
governance" above). The direct tool preserves that governance by letting VBW set
each worker's model explicitly; the keyword does not.

## Result-bridging rule (mandatory for gated artifacts)

A workflow's output is the **final answer in the session context**, not a durable
artifact. For **gated** artifacts — a plan, a plan `SUMMARY.md`, or a
`VERIFICATION.md` — the orchestrator MUST bridge that result into the VBW
artifact the step stands for.

- The orchestrator is the **sole writer** of gated VBW lifecycle artifacts.
- A workflow **must never write a gated `.vbw-planning/` artifact directly**. Doing
  so would bypass `file-guard.sh`, the contracts, and the gate system.
- `delegation_mode=workflow` is a recognized marker value. Per `file-guard.sh` and
  `agent-spawn-guard.sh` (which special-case only `team`), it is treated as a
  non-team mode and receives **no** team-style write bypass.

### Carve-out: read-only map codebase docs (deliberate design decision)

The read-only codebase map docs under `.vbw-planning/codebase/` are **not** gated
artifacts — they have no contract and no gate, unlike plans/summaries/verification.
For the `/vbw:map` path specifically, the workflow's `vbw:vbw-scout` workers MAY
write the seven `codebase/*.md` docs **directly via `<output_paths>`** — exactly as
the existing team `Step 3-quad` path already does — and return only `cross_cutting`
summaries. These are the same `vbw:vbw-scout` agents the team path already trusts to
write those docs, governed by the same `file-guard.sh` rules.

This is a deliberate decision, not a weakening of the guard rationale. Bridging
exists to keep the orchestrator the sole writer of *gated* state and to keep heavy
intermediate output out of context. Forcing the orchestrator to bridge the map docs
would make the workflow return all seven docs' full content (~900 lines) just so the
orchestrator could re-write them verbatim — a real payload regression with no guard
benefit, since these docs are ungated. The carve-out keeps the map workflow path's
payload as light as the team path. **Gated artifacts (plans, `SUMMARY.md`,
`VERIFICATION.md`) are unaffected — bridging stays mandatory for them, and the
`delegation_mode=workflow` no-bypass invariant is preserved: the carve-out adds no
write bypass; it relies solely on `.vbw-planning/codebase/` being ungated.**

### Enforcement parity

Workflow workers are normal subagents: they are subject to the same project
`SubagentStart`/`PreToolUse` hooks and the same file/spawn guards as `Task`-spawned
subagents (verified empirically — the project's `.claude/settings.json` overlays
injected context and fired/blocked inside the workflow-spawned `vbw:vbw-scout`
agents identically to team/Task subagents). Per-repo policy overlays (lint gates,
CMM/ctx nudges, file guards) keep working under the workflow executor with no
special handling.

## Backward compatibility (top invariant)

When the runtime lacks workflow support (the user's Claude config has not enabled
Dynamic Workflows) **or** a step is not parallel (fan-out < 2), behavior is
identical to today's VBW — `prefer_workflows` has no effect there, and it fails
closed. `prefer_workflows=never` guarantees the legacy team/subagent path
everywhere. Where the runtime **does** support workflows, the default `auto` makes
a workflow the preferred backend for parallel work (Agent Teams become the
fallback). No phase, plan, gate, or verification semantics change on either path.

## What the official docs resolved

- **Saved workflow location.** Saved workflows live in `.claude/workflows/`
  (project, shared via the repo) or `~/.claude/workflows/` (home, personal) and
  run as `/<name>`; a project workflow wins over a personal one with the same
  name. The docs document **no plugin-bundled workflow mechanism** — there is no
  documented way to ship a `.js` workflow from the marketplace plugin cache. So
  VBW does **not** rely on a bundled workflow file. The orchestrator emits the
  per-request `ultracode` keyword to generate an **ephemeral** workflow on demand
  (no saved file required), which also keeps VBW's behavior self-contained.
- **Subagents are the worker primitive.** The docs state workflows orchestrate
  subagents and link custom-subagent creation as "the worker primitive workflows
  orchestrate," indicating custom/named subagents (incl. `vbw-*`) are the intended
  workers. **Confirmed empirically:** a workflow script targets a specific agent via
  `agent(prompt, { agentType: 'vbw:vbw-scout' })`, where `agentType` resolves from
  the same registry as the Agent tool and spawns the exact plugin-namespaced agent.
- **Run artifacts.** Each run writes its script under the session directory in
  `~/.claude/projects/`, and additionally per-agent transcripts (`agent-*.jsonl`)
  plus a run journal (`journal.jsonl`) under
  `<session>/subagents/workflows/<runId>/` — cleanly isolated from the main-session
  transcript and useful for `/vbw:doctor`-style inspection of which executor
  actually ran. None of it is written under `.vbw-planning/`, so result-bridging for
  gated artifacts stays mandatory.

## Settings keys (one resolved empirically)

Two distinct boolean keys govern workflow availability:

- **`disableWorkflows`** — the org/user **kill switch** documented on the public
  workflows page. `true` anywhere disables.
- **`enableWorkflows`** — the **Pro opt-in** toggle. Confirmed empirically: the
  `/config` "Dynamic workflows" row and the cloud/admin settings persist the
  toggle as `"enableWorkflows": true|false` in `settings.json` (e.g.
  `~/.config/claude-code/settings.json`), **not** as `disableWorkflows`. On Pro
  the feature is OFF until `enableWorkflows` is true, so `enableWorkflows:false`
  is a definitive "unsupported" signal. `detect-workflows-support.sh` reads both
  keys: the kill switch wins, then `enableWorkflows:false` → unsupported,
  `enableWorkflows:true` → supported; absence of both stays optimistic
  (supported) with the runtime as final authority.

## Resolved questions

Both questions that previously gated deeper wiring are now resolved (confirmed by a
live Opus 4.8 run — see `workflow-executor-empirical-notes.md`):

- **Programmatic dispatch (was open).** A workflow can be dispatched
  programmatically without a human typing a keyword: the orchestrator calls the
  first-class `Workflow` tool directly (`Workflow({ script })`). The per-request
  `ultracode` keyword remains as an alternate trigger where the tool is absent.
- **Targeting a specific `vbw-*` worker (was open).** A workflow script targets a
  named agent via `agent(prompt, { agentType: 'vbw:vbw-scout' })`; `agentType`
  resolves from the same registry as the Agent tool, spawning the exact
  plugin-namespaced agent.

As a conservative prototype, wiring stays limited to the opt-in `/vbw:map` path and
the detection/resolution scaffolding, all defaulting to the existing behavior.
