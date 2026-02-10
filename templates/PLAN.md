<!-- VBW PLAN TEMPLATE (ARTF-01) -- Replace {placeholders} with actual content -->
---
phase: {phase-id}
plan: {plan-number}
title: {plan-title}
type: execute
wave: {wave-number}
depends_on: [{dependency-list}]
cross_phase_deps:
  - phase: {N}
    plan: "{NN-MM}"
    artifact: "{file-path}"
    reason: "{why-this-dependency-exists}"
autonomous: {true|false}
effort_override: {thorough|balanced|fast|turbo}
skills_used:
  - {skill-name}
files_modified:
  - {file-path}

must_haves:
  truths:
    - "{invariant-that-must-be-true-after-execution}"
  artifacts:
    - path: "{file-path}"
      provides: "{what-this-file-delivers}"
      contains: "{string-that-must-exist}"
  key_links:
    - from: "{source-artifact}"
      to: "{target-artifact}"
      via: "{relationship-description}"
---

<!-- Objective: What this plan achieves and why it matters -->
<objective>
{objective-description}
</objective>

<!-- Context: Files the executing agent should read before starting -->
<context>
@{context-file-1}
@{context-file-2}
</context>

<!-- Tasks: Sequential steps. Each task = one atomic commit. -->
<tasks>

<task type="auto">
  <name>{task-name}</name>
  <files>
    {file-1}
    {file-2}
  </files>
  <action>
{what-to-do}
  </action>
  <verify>
{how-to-verify}
  </verify>
  <done>
{criteria-for-completion}
  </done>
</task>

<!-- Add checkpoint tasks where user verification is needed -->
<!-- <task type="checkpoint:human-verify"> -->

</tasks>

<!-- Verification: Checks run after all tasks complete -->
<verification>
1. {check-description}
2. {check-description}
</verification>

<!-- Success Criteria: High-level outcomes that define plan success -->
<success_criteria>
- {criterion-1}
- {criterion-2}
</success_criteria>

<output>
{path-to-summary-file}
</output>
