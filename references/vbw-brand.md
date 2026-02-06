# VBW Brand Vocabulary

Single source of truth for all VBW visual output formatting.

## Semantic Symbols

| Meaning          | Symbol | Unicode  | Usage                    |
|------------------|--------|----------|--------------------------|
| Success/complete | ✓      | U+2713   | Task done, check passed  |
| Failure/error    | ✗      | U+2717   | Task failed, check error |
| In progress      | ◆      | U+25C6   | Currently executing      |
| Pending/queued   | ○      | U+25CB   | Waiting to start         |
| Action/lightning | ⚡     | U+26A1   | Command invocation       |
| Warning          | ⚠      | U+26A0   | Non-blocking concern     |
| Info/arrow       | ➜      | U+279C   | Navigation, next step    |

## Box Drawing

### Critical / Phase-level (double-line)

```
╔══════════════════════════════╗
║  Phase 1: Core Framework     ║
║  Status: In Progress         ║
╚══════════════════════════════╝
```

Characters: ╔ (U+2554) ═ (U+2550) ╗ (U+2557) ║ (U+2551) ╚ (U+255A) ╝ (U+255D)

### Standard / Task-level (single-line)

```
┌──────────────────────────────┐
│  Task 1: Create agent stubs  │
│  Status: ✓ Complete          │
└──────────────────────────────┘
```

Characters: ┌ (U+250C) ─ (U+2500) ┐ (U+2510) │ (U+2502) └ (U+2514) ┘ (U+2518)

## Progress Bars

Format: `[filled][empty]` using block elements.

- Filled: █ (U+2588)
- Empty: ░ (U+2591)

Examples:
- 0%:   `░░░░░░░░░░`
- 30%:  `███░░░░░░░`
- 70%:  `███████░░░`
- 100%: `██████████`

Pair with percentage: `███████░░░ 70%`

## Rules

1. No ANSI color codes -- not rendered in Claude Code model output
2. No Nerd Font glyphs -- not universally available
3. Content must be readable even if box-drawing fails to render
4. Keep lines under 80 characters inside boxes
5. Use semantic symbols consistently across all agent output
6. Progress bars always 10 characters wide for visual consistency
