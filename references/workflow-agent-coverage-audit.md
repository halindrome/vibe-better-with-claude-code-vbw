# Workflow Agent Coverage Audit

Status: analysis (2026-06-17). Audits which of VBW's 7 agents can benefit from the
Dynamic Workflow executor backend, scored against the eligibility criterion in
`workflow-executor.md`. Companion to `workflow-executor-empirical-notes.md`.

## Eligibility criterion (from `workflow-executor.md`)

A step is workflow-eligible when it is **Wide + Parallel + Bounded**:

- **Wide** — fans out across many independent units beyond the configured threshold.
- **Parallel** — units have no ordering dependency on each other.
- **Bounded** — the unit set is enumerable up front; each unit is self-contained.

Disqualifiers: ordered work, anything needing VBW gates/QA *between* units, single-unit work.

## Framing bias to correct

The feature originated as "**replace VBW's existing team/subagent fan-out** with workflows"
(motivating bug: `/vbw:map` collapsing its Scout tiers to solo). That lens only surfaces
agents that *already* spawn teams. Agents whose fan-out opportunity is latent — they do not
spawn teams today but *could* fan out — were structurally invisible. The audit below
deliberately scores latent fan-out, not just existing team spawns.

## Current wiring (verified on `feat/workflows-executor-backend`)

Real executor dispatch (preflight: `normalize-workflows-mode` → `detect-workflows-support`
→ `resolve-executor --mode --fanout`):

| Path | Agent(s) | Fan-out unit | Shape |
| :--- | :--- | :--- | :--- |
| `execute-protocol.md` | Lead → Dev (workers) | plans in a dependency wave (fan-out ≥ 2) | parallel-plan execution |
| `map.md` | Scout | scan/research domains | multi-modal sweep |
| `debug.md` | Debugger | competing hypotheses (`--competing`/`--parallel`) | hypothesis cohort |

## Per-agent scoring

| Agent | Wide+Parallel+Bounded? | Best workflow shape | Wired? | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| Scout | Yes | sweep + verify | ✅ | done |
| Lead (execute) | Yes | parallel-plan execution | ✅ | done |
| Debugger | Yes | hypothesis cohort | ✅ | done |
| **QA** | **Partial** — per-plan verify parallel *within* a round; round loop + gate are sequential/holistic | parallel per-plan verify + holistic synthesis tail | ❌ | **#1 gap (shape-constrained)** |
| **Architect** | Yes (medium) | judge-panel over N candidate decompositions; parallel success-criteria derivation | ❌ | real gap |
| **Lead (planning)** | Yes (medium) | judge-panel to *generate* the plan set (distinct from dispatching it) | ❌ | gap |
| Dev (normal exec) | No — tasks ordered, atomic commit per task | none | n/a (worker only) | correctly excluded |
| **Dev (competing impl)** | Yes (opt-in only) | K implementations of one task → judge → keep best | ❌ | candidate, token-expensive |
| Docs | Marginal — needs consistency barrier, low volume/phase | parallel doc-gen + synthesis | ❌ | lowest priority |

## Gaps, ranked

1. **QA — `verify.md`** (real candidate, shape-constrained — downgraded from "slam-dunk").
   `verify.md` was never touched on this branch (no deliberate exclusion — simply never
   reached). QA is **three layers, and only the middle one fans out**:

   - **Layer 1 — round loop (sequential, NOT parallel).** Remediation round R re-checks
     the prior rounds' FAIL checks (`R{RR}-VERIFICATION.md`, "VERIFICATION HISTORY") and
     re-evaluates the phase KNOWN ISSUES backlog. Round N+1 depends on round N's fixes.
     Owned by the orchestrator + `qa-result-gate.sh`. Stays with VBW.
   - **Layer 2 — single-round per-plan verification (THE fan-out unit).** Goal-Backward
     step 3 is explicitly per-plan: compare *each PLAN.md's* deliverables vs its SUMMARY.md
     vs code ("highest-value QA function"). In a multi-plan phase these are independent →
     `parallel(plans.map(verify))`. Today one QA agent does all N plans serially in one
     invocation; that is what splits.
   - **Layer 3 — gate / aggregation (holistic, but already deterministic bash).** Phase
     verdict aggregation, freshness (`verified_at_commit`), known-issues reconciliation,
     roadmap routing (`needs_verification`/`needs_reverification`). Not LLM fan-out — it is
     the synthesis barrier that *consumes* Layer 2, not work to parallelize.

   This is the **same composition as the execute path**: offload the one wide step
   (Layer 2), keep the loop and gate (Layers 1 & 3) in VBW. The design doc's "no gates/QA
   *between* units" disqualifier refers precisely to Layers 1 & 3, which VBW retains.

   **Caveat (not embarrassingly parallel):** cross-plan *integration* checks (the
   "Deep: + cross-file" tier — does plan B correctly use plan A's interface?) span plans
   and cannot be partitioned per-plan. So the honest shape is **parallel per-plan + a
   holistic synthesis tail**, not a pure Scout-style sweep. Payoff scales with plan count:
   worth it for large multi-plan phases (10+; real wall-clock + context savings, each plan
   verified in an isolated worker returning only findings), marginal for ≤3 plans.

   Implementation: mirror `debug.md`'s preflight, fan-out set = the phase's plans within a
   single round, synthesis stage performs cross-plan integration checks, then hand to the
   existing `qa-result-gate.sh`.

2. **Architect / Lead-planning.** Two latent shapes: (a) judge-panel over N candidate
   roadmap/plan decompositions → score → synthesize; (b) parallel success-criteria
   derivation per requirement. One-shot upfront steps, lower frequency than QA.

3. **Dev competing-implementations (opt-in).** See below.

4. **Docs.** Parallel generation of independent doc artifacts, but usually wants a global
   consistency synthesis pass (barrier) and volume per phase is low. Lowest value.

## Dev: reconsidered

Dev's *normal* execution is correctly excluded — ordered tasks, one atomic commit each,
no internal fan-out; Dev only ever participates as a *worker* inside the execute-path
workflow. But there is a distinct, legitimate shape: **competing implementations** —
generate K independent implementations of a single marked task, judge against a rubric
(optionally run tests per variant), keep the best, discard the rest. This mirrors the
Debugger's existing `--competing` cohort.

Frictions that make it **opt-in per task, never automatic**:

- **Isolation** — K parallel variants must each run in `isolation: 'worktree'` to avoid
  clobbering the working tree. Expensive (disk + setup per variant).
- **Judging** — code quality is noisier to judge than research findings; needs an explicit
  rubric and possibly a test run per variant (a verify gate inside the tournament).
- **Token cost** — K× the tokens of a single implementation. This directly tensions with
  VBW's fewer-tokens philosophy, so it must be explicitly requested for high-uncertainty /
  high-value tasks only (tricky algorithm, perf-critical path, API shape with several
  plausible designs).
- **Commit contract** — only the winning variant commits; result-bridging returns the
  winning diff for VBW to apply + commit in the durable tree.

Recommendation: a `--competing` flag on the relevant Dev entry (parallel to Debugger),
gated behind the per-agent config below. Not part of automatic routing.

## Per-agent workflow control (proposed)

Today `prefer_workflows` is a single global scalar in `config.json` (`"auto"`), alongside
`workflow_max_workers`. VBW already has per-agent **model** granularity via
`model-profiles.json` (profile → per-agent model) resolved by `resolve-agent-model.sh
<agent>`. Workflows should get the analogous per-agent control, for the same
token-budget-governance reason.

Proposed (backward-compatible) shape — `prefer_workflows` accepts a scalar OR an object:

```jsonc
// scalar (current behavior — applies to every agent)
"prefer_workflows": "auto"

// object (per-agent override + default)
"prefer_workflows": {
  "default": "auto",
  "scout": "auto",
  "qa": "auto",
  "architect": "never",
  "dev": "never"
}
```

Resolution mirrors `resolve-agent-model.sh`: `normalize-workflows-mode.sh <config> <role>`
returns the per-role override if present, else `default`, else `"auto"`. A scalar value is
treated as `default` for all roles, so existing configs keep working unchanged. Each
command's preflight already calls `normalize-workflows-mode.sh .vbw-planning/config.json`;
it gains a trailing role argument.

## How to test each gap (decoupled fixtures, not one giant phase)

A "complex phase with many parallel plans" exercises only the **execute** path, which is
already wired — by construction it cannot surface any gap below. Each gap needs its own
deterministic fixture:

- **QA** — a multi-plan phase (10+ plans) within a single round → assert `verify` fans out
  per-plan verification at fan-out ≥ threshold, runs the holistic synthesis tail
  (cross-plan integration), then hands to `qa-result-gate.sh`; assert the round loop stays
  sequential and identical behavior when workflows are unsupported. NOTE: this is the same
  "complex phase with many plans" fixture originally imagined for the execute path — it is
  the correct fixture for QA, not execute (which is already wired).
- **Architect / Lead-planning** — a roadmap/plan step with several viable decompositions →
  assert a judge-panel runs and synthesizes a winner.
- **Dev competing** — a single task marked `--competing` → assert K isolated variants run,
  one wins, only the winner commits.
- **Docs** — N independent doc artifacts → assert parallel generation + a consistency pass.
