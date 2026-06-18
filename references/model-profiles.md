# Model Profiles

**Purpose:** Control AI model selection for VBW agents to optimize cost vs quality tradeoff.

## Overview
VBW spawns 7 specialized agents (Lead, Dev, QA, Scout, Debugger, Architect, Docs) via the Task tool. Model profiles determine which Claude model each agent uses. Three preset profiles cover common use cases, with per-agent overrides for advanced customization.

## Preset Profiles

### Quality (default)
**Use when:** Architecture decisions, production-critical work, anything embarrassing to get wrong.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Lead | opus | Maximum planning depth and research quality |
| Dev | opus | Complex implementation, deep reasoning |
| QA | sonnet | Solid verification without Opus cost |
| Scout | sonnet | Research quality with MCP tool access |
| Debugger | opus | Root cause analysis needs deep reasoning |
| Architect | opus | Roadmap and phase structure requires strategic thinking |
| Docs | sonnet | Documentation tasks benefit from clear prose without Opus cost |

**Est. cost per phase:** ~$3.00 (baseline)

### Balanced
**Use when:** Standard development work, most phases.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Lead | sonnet | Good planning quality, 5x cheaper than Opus |
| Dev | sonnet | Solid implementation for most tasks |
| QA | sonnet | Standard verification depth |
| Scout | sonnet | Research quality, MCP tool access |
| Debugger | sonnet | Good debugging for common issues |
| Architect | sonnet | Clear roadmaps without Opus overhead |
| Docs | sonnet | Standard documentation quality |

**Est. cost per phase:** ~$1.50 (50% of Quality)

### Budget
**Use when:** Prototyping, exploratory work, tight budget constraints.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Lead | sonnet | Minimum viable planning (Haiku too weak) |
| Dev | sonnet | Maintains code quality baseline |
| QA | haiku | Quick verification, 25x cheaper |
| Scout | haiku | Fast research, minimal cost |
| Debugger | sonnet | Root cause needs Sonnet minimum |
| Architect | sonnet | Roadmap clarity worth Sonnet cost |
| Docs | sonnet | Maintains documentation quality baseline |

**Est. cost per phase:** ~$0.70 (25% of Quality, 50% of Balanced)

## Per-Agent Overrides
Override individual agents without switching profiles.

**Syntax (via /vbw:config):**
```
/vbw:config model_override <agent> <model>
```

**Example:**
```
/vbw:config model_override dev opus
```
Sets Dev to Opus while keeping other agents at profile defaults.

**When to override:**
- Dev to Opus on budget profile for complex implementation tasks
- QA to Sonnet on budget profile for critical verification
- Lead to Opus on balanced profile for strategic planning phases

**Clearing overrides:**
Switch to a different profile and back, or manually edit .vbw-planning/config.json.

## Per-Phase Model Override

Beyond per-agent overrides, an individual **plan** can raise or lower its Dev model via a `model_override` frontmatter field (`opus|sonnet|haiku|fable`), set by `vbw-lead` from plan complexity. It is **absent by default** — set only when a plan clearly departs from the profile (raise for high-complexity/high-risk work, lower for trivial/mechanical work).

**Resolution precedence (most specific wins):**
```
plan model_override  →  config model_overrides[agent]  →  model_profile preset
```
`resolve-agent-model.sh` accepts the plan's `model_override` as an optional 4th argument, and the execute dispatch reads each plan's frontmatter and threads it per Dev spawn. Disable entirely with `phase_model_selection: false` (default `true`).

## Review Downgrade (prover-verifier asymmetry)

With `review_model_downgrade: true` (default `false`), QA runs **one tier below the phase's build model** — the highest tier used across the phase's plans (`fable → opus → sonnet → haiku`, floored at haiku) — so the verifier is cheaper than the builder. `model-tier-down.sh` computes the step. Off (default), QA uses its normally-resolved model.

## Cost Comparison

| Profile | Lead | Dev | QA | Scout | Docs | Est. Cost/Phase | vs Quality |
|---------|------|-----|----|----|------|-----------------|------------|
| Quality | opus | opus | sonnet | sonnet | sonnet | $3.00 | 100% |
| Balanced | sonnet | sonnet | sonnet | sonnet | sonnet | $1.50 | 50% |
| Budget | sonnet | sonnet | haiku | haiku | sonnet | $0.70 | 25% |

*Estimates based on typical 3-plan phase with 2 Dev teammates, 1 QA run, Lead planning. Assumes ~15K input + ~5K output tokens per agent turn. Opus ~$15/$75 per MTok, Sonnet ~$3/$15, Haiku ~$0.25/$1.25 (input/output). Actual costs vary by phase complexity and plan count.*

## Configuration

**View current profile:**
```
/vbw:config
```
Shows active profile and per-agent model assignments in settings table.

**Switch profile:**
```
/vbw:config model_profile <quality|balanced|budget>
```
Displays before/after cost impact estimate.

**Config file location:**
`.vbw-planning/config.json` -- fields: `model_profile` (string), `model_overrides` (object), `phase_model_selection` (bool, default `true`), `review_model_downgrade` (bool, default `false`)

## Implementation Notes
- Model resolution: `scripts/resolve-agent-model.sh` reads config, applies profile preset, merges overrides
- Turn-budget resolution: `scripts/resolve-agent-max-turns.sh` reads config `agent_max_turns` and scales by effort. Set a value to `false` or `0` to give that agent unlimited turns — the resolver emits an empty string, and the orchestrator omits the `maxTurns` parameter from the Task tool call
- Task tool integration: All agent-spawning commands pass explicit `model` and `maxTurns` parameters. When the resolver emits a non-empty value (positive integer), `maxTurns` is included; when the resolver emits an empty value (unlimited), `maxTurns` is omitted entirely
- Turbo effort bypasses model logic (no agents spawned, direct execution)
- Model names (tier aliases the runtime resolves to the current model per tier): `fable` = Claude Fable 5, `opus` = Claude Opus 4.8, `sonnet` = Claude Sonnet 4.6, `haiku` = Claude Haiku 4.5. `fable` is reachable only via a per-plan `model_override` or a `model_overrides` entry — the preset profiles use only opus/sonnet/haiku.

## Related Documentation
- Effort vs Model: @references/effort-profile-balanced.md (effort controls workflow depth, model profile controls cost)
- Command reference: @commands/help.md
- User guide: @README.md Cost Optimization section
