---
name: vbw:doctor
disable-model-invocation: true
description: Run health checks on VBW installation and project setup.
allowed-tools: Read, Bash, Glob, Grep
---

# VBW Doctor

## Context

Working directory: `!`pwd``
Version: `!`cat VERSION 2>/dev/null || echo "none"``

## Checks

Run ALL checks below. For each, report PASS or FAIL with a one-line detail.

### 1. jq installed
`jq --version 2>/dev/null || echo "MISSING"`
FAIL if missing: "Install jq: brew install jq (macOS) or apt install jq (Linux)"

### 2. VERSION file exists
Check `VERSION` in repo root. FAIL if missing.

### 3. Version sync
`bash scripts/bump-version.sh --verify 2>&1`
FAIL if mismatch detected.

### 4. Plugin cache present
Check `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/vbw-marketplace/vbw/` exists and has at least one version directory. FAIL if empty or missing.

### 5. hooks.json valid
Parse `hooks/hooks.json` with `jq empty`. FAIL if parse error.

### 6. Agent files present
Glob `agents/vbw-*.md`. Expect 6 files (lead, dev, qa, scout, debugger, architect). FAIL if any missing.

### 7. Config valid (project only)
If `.vbw-planning/config.json` exists, parse with `jq empty`. FAIL if parse error. SKIP if no project initialized.

### 8. Scripts executable
Check all `scripts/*.sh` files. WARN if any lack execute permission.

### 9. gh CLI available
`gh --version 2>/dev/null || echo "MISSING"`
WARN if missing: "Install gh for /vbw:release GitHub integration."

### 10. sort -V support
`echo -e "1.0.2\n1.0.10" | sort -V 2>/dev/null | tail -1`
PASS if result is "1.0.10". WARN if sort -V unavailable (fallback will be used).

## Output Format

```
VBW Doctor v{version}

  1. jq installed          {PASS|FAIL} {detail}
  2. VERSION file          {PASS|FAIL}
  3. Version sync          {PASS|FAIL} {detail}
  4. Plugin cache          {PASS|FAIL} {detail}
  5. hooks.json valid      {PASS|FAIL}
  6. Agent files           {PASS|FAIL} {count}/6
  7. Config valid          {PASS|FAIL|SKIP}
  8. Scripts executable    {PASS|WARN} {detail}
  9. gh CLI                {PASS|WARN}
 10. sort -V support       {PASS|WARN}

Result: {N}/10 passed, {W} warnings, {F} failures
```

Use checkmark for PASS, warning triangle for WARN, X for FAIL.
