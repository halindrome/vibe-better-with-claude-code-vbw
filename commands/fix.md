---
name: vbw:fix
category: supporting
description: Apply a quick fix or small change with commit discipline. Turbo mode -- no planning ceremony.
argument-hint: "<description of what to fix or change>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# VBW Fix: $ARGUMENTS

## Context
Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``
Config: Pre-injected by SessionStart hook.

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No $ARGUMENTS: STOP "Usage: /vbw:fix \"description of what to fix\""

## Steps
1. **Parse:** Entire $ARGUMENTS (minus flags) = fix description.

2. **Milestone:** If `.vbw-planning/ACTIVE` exists, use milestone-scoped
   `STATE_PATH`. Else `.vbw-planning/STATE.md`.

3. **Spawn Dev:** Resolve model first:
    ```bash
    DEV_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh dev .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
    DEV_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh dev .vbw-planning/config.json turbo)
    ```

    Spawn vbw-dev as subagent via Task tool with `model: "${DEV_MODEL}"` and
    `maxTurns: ${DEV_MAX_TURNS}`:

    ```text
    Quick fix (Turbo mode). Effort: low.
    Task: {fix description}.
    If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before implementing.
    Implement directly. One atomic commit: fix(quick): {brief description}.
    No SUMMARY.md or PLAN.md needed.
    If tests reveal pre-existing failures unrelated to this fix, list them in your response under a "Pre-existing Issues" heading with test name, file, and failure message.
    If ambiguous or requires architectural decisions, STOP and report back.
    ```

4. **Verify + present:** Check `git log --oneline -1`. Check Dev response for pre-existing issues.
    Committed, no discovered issues:

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}
    ```

    Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh fix` and display.

    Committed, with discovered issues (Dev reported pre-existing failures):

    De-duplicate by test name and file (keep first error message when the same
    test+file pair has different messages). Cap the list at 20 entries; if more
    exist, show the first 20 and append `... and {N} more`.

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}

      Discovered Issues:
        ⚠ testName (path/to/file): error message
        ⚠ testName (path/to/file): error message
      Suggest: /vbw:todo <description> to track
    ```

    This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT
    invoke /vbw:todo, and do NOT enter an interactive loop. The user decides
    whether to track these. If no discovered issues: omit the section entirely.
    After displaying discovered issues, STOP. Do not take further action.
    Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh fix` and display.

    Dev stopped:

    ```text
    ⚠ Fix could not be applied automatically
      {reason from Dev agent}
    ```

    Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh debug` and display.