# Model-Per-Teammate Cost Evaluation

Analysis of current model assignments across all VBW agent roles, evaluating whether the existing effort-profile-driven model split is cost-optimized.

## Summary Table

| Agent Role | Current Assignment | Token Pattern | Quality Sensitivity | Recommended | Change? |
|------------|-------------------|---------------|---------------------|-------------|---------|
| Scout      | Haiku (frontmatter) | Low           | Low                 | Haiku       | No      |
| Architect  | Inherit (Opus/Sonnet) | High     | High                | Inherit     | No      |
| Lead       | Inherit (Opus/Sonnet) | Highest  | Critical            | Inherit     | No      |
| Dev        | Inherit (Opus/Sonnet) | High     | Tier-dependent      | Inherit     | No      |
| QA         | Sonnet (frontmatter) | Medium   | Tier-dependent      | Sonnet      | No      |
| Debugger   | Inherit (Opus/Sonnet) | Medium-High | High for complex bugs | Inherit | No      |

**Verdict: CONFIRM CURRENT ASSIGNMENTS -- no changes required.**

---

## 1. Current Assignments

Source: `references/effort-profiles.md`

### Model Selection Architecture

Agent frontmatter uses `model: inherit` for Lead, Dev, Debugger, and Architect. Scout uses `model: haiku` and QA uses `model: sonnet` (both hardcoded in frontmatter). For inherit agents, model selection defers to the effort profile level, which maps to concrete models:

- **Thorough / Balanced profiles:** Opus (maximum capability)
- **Fast / Turbo profiles:** Sonnet (cost-reduced, still capable)

### Per-Agent Model Assignment

| Agent     | Frontmatter Model | Thorough | Balanced | Fast   | Turbo  |
|-----------|-------------------|----------|----------|--------|--------|
| Scout     | haiku (frontmatter) | Haiku    | Haiku    | Haiku  | skip   |
| Architect | inherit           | Opus     | Opus     | Sonnet | skip   |
| Lead      | inherit           | Opus     | Opus     | Sonnet | skip   |
| Dev       | inherit           | Opus     | Opus     | Sonnet | Sonnet |
| QA        | sonnet (frontmatter) | Sonnet   | Sonnet   | Sonnet | skip   |
| Debugger  | inherit           | Opus     | Opus     | Sonnet | Sonnet |

At Turbo, only Dev and Debugger are spawned. All other roles are skipped.

---

## 2. Cost Analysis Per Agent Role

### Scout

- **Token consumption pattern:** Low. Performs targeted web lookups and brief codebase searches. Outputs are short factual summaries (URLs, version numbers, API references). Typical token consumption is the lowest of any agent role.
- **Quality sensitivity:** Low. Scout output is informational, not generative. Haiku can retrieve web pages and extract facts as effectively as larger models. The task is retrieval, not reasoning.
- **Current assignment fitness:** Optimal. Haiku is hardcoded in the agent frontmatter, which is correct -- there is no scenario where Scout needs Opus-level reasoning. The hardcoded assignment avoids unnecessary cost at all effort levels.

### Architect

- **Token consumption pattern:** High. Reads the full codebase context (STATE.md, ROADMAP.md, REQUIREMENTS.md, existing code), analyzes scope, and produces detailed plan files with YAML frontmatter, task decomposition, verification criteria, and must_haves. At Thorough effort, output includes traceability matrices and comprehensive self-review.
- **Quality sensitivity:** High. Plans drive all downstream execution. A poorly structured plan causes cascading issues: incorrect task decomposition leads to missed requirements, bad dependency ordering causes blocked teammates, weak verification criteria let bugs through. Plan quality is the single biggest lever on overall execution quality.
- **Current assignment fitness:** Appropriate. Opus at Thorough/Balanced provides the deep reasoning needed for comprehensive planning. Sonnet at Fast is acceptable because Fast profiles explicitly trade plan depth for speed. The `model: inherit` pattern correctly handles both cases.

### Lead

- **Token consumption pattern:** Highest of all agents. The lead orchestrates entire phase execution: reads all plans, creates and manages teammate tasks, monitors wave transitions, handles state file updates, coordinates inter-teammate communication, manages shutdown sequences, and writes execution state JSON. Long-running with many tool calls.
- **Quality sensitivity:** Critical. Orchestration errors cascade to all teammates. Incorrect wave dependency wiring causes execution order violations. Missed resume state causes duplicate work. Poor teammate coordination leads to conflicts. The lead's orchestration quality determines whether the entire agent team functions correctly.
- **Current assignment fitness:** Appropriate. Opus at Thorough/Balanced is justified by the orchestration complexity. Sonnet at Fast is acceptable because Fast efforts have simpler execution patterns (fewer waves, less inter-teammate coordination). At Turbo, the lead is not spawned at all (Dev executes directly), which is the correct cost optimization.

### Dev

- **Token consumption pattern:** High. Reads plan files, implements code changes (Write/Edit), runs verification commands (Bash), and creates atomic commits. Token consumption scales with implementation complexity -- a simple config change uses far fewer tokens than a multi-file feature implementation.
- **Quality sensitivity:** Tier-dependent. At Thorough effort, Dev handles complex implementations where reasoning depth directly impacts code quality (architecture decisions, edge case handling, error recovery patterns). At Fast/Turbo, tasks are typically well-defined and straightforward, requiring less reasoning depth.
- **Current assignment fitness:** Already optimized. The two-tier split (Opus at Thorough/Balanced, Sonnet at Fast/Turbo) matches the quality-sensitivity curve. Thorough tasks justify Opus cost. Fast/Turbo tasks are simple enough for Sonnet. The plan_mode_required gate at Thorough adds an additional quality checkpoint that leverages Opus reasoning.

### QA

- **Token consumption pattern:** Medium. Reads PLAN.md and SUMMARY.md artifacts, runs verification checks, scans for anti-patterns, and produces verification reports. Token consumption varies by tier: high tier (30+ checks with full anti-pattern scan) vs low tier (5-10 quick checks).
- **Quality sensitivity:** Tier-dependent. Deep verification (Thorough) requires Opus-level reasoning to catch subtle issues: requirement-to-artifact traceability gaps, cross-file consistency problems, convention violations. Quick verification (Fast) is primarily mechanical checking (file exists, frontmatter valid, key strings present) that Sonnet handles well.
- **Current assignment fitness:** Appropriate. Opus at Thorough/Balanced handles deep verification. Sonnet at Fast handles quick verification. At Turbo, QA is skipped entirely (correct -- the user judges output directly). The existing split aligns with the quality requirements of each tier.

### Debugger

- **Token consumption pattern:** Medium-high. Generates hypotheses, gathers evidence across multiple files, tests hypotheses sequentially, implements fixes, and runs regression checks. Token consumption depends on bug complexity -- simple issues resolve quickly, while complex bugs require exhaustive investigation.
- **Quality sensitivity:** High for complex bugs (Thorough), moderate for simple fixes (Fast/Turbo). At Thorough effort, the debugger tests all 3 hypotheses even if the first seems confirmed, producing comprehensive investigation reports. This deep analysis requires strong reasoning. At Turbo, single-hypothesis rapid fix-and-verify is sufficient.
- **Current assignment fitness:** Appropriate. Opus at Thorough/Balanced provides the reasoning depth needed for exhaustive hypothesis testing and comprehensive regression analysis. Sonnet at Fast/Turbo handles targeted fix-and-verify cycles. The split matches the debugging complexity expected at each effort level.

---

## 3. Recommendation

**Verdict: CONFIRM CURRENT ASSIGNMENTS**

### Rationale

The existing two-tier model split is already cost-optimized:

1. **Opus for Thorough/Balanced:** These effort levels demand deep reasoning, comprehensive analysis, and high-quality orchestration. Opus is justified for all agent roles at these levels.

2. **Sonnet for Fast/Turbo:** These effort levels explicitly trade depth for speed. Tasks are well-defined, verification is lighter, and the simpler execution patterns do not require Opus-level reasoning.

3. **Haiku for Scout (hardcoded):** Scout's retrieval-focused workload never benefits from larger models. Hardcoding Haiku avoids unnecessary cost regardless of effort level.

4. **`model: inherit` pattern:** Deferring model selection to the effort profile level is the correct abstraction. It centralizes the cost/quality tradeoff decision in one place (effort-profiles.md) rather than scattering it across individual agent definitions.

### Potential Future Optimization

If Claude Code exposes per-agent token usage metrics in the future, one area to re-evaluate:

- **QA at Balanced** could potentially drop to Sonnet without quality regression. QA's standard tier (15-25 checks) is less reasoning-intensive than the deep tier (30+ checks). However, this would require the `model: inherit` pattern to support per-agent overrides at specific effort levels, which would add complexity to the current clean two-tier split. The cost savings would be marginal (QA is medium token consumption, Balanced is one of four profiles). Not recommended without usage data to confirm.

---

## 4. Implementation Impact

**No code changes required.**

This evaluation confirms the current architecture is sound:

- `references/effort-profiles.md` -- Profile Matrix and Per-Agent Model Assignment remain as-is
- Agent frontmatter `model: inherit` pattern -- no changes needed
- Scout `model: haiku` hardcoding -- confirmed as correct
- No new configuration options, no agent file modifications, no profile adjustments

The effort-profiles reference document and agent definitions require zero modifications based on this analysis.
