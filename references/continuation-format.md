# VBW Continuation Format

Template for the structured message presented when resuming a session.

## Template

```
╔══════════════════════════════════════╗
║  {project-name}                      ║
║  Core value: {core-value}            ║
╚══════════════════════════════════════╝

Position
  Phase: {phase-number} of {total-phases} ({phase-name})
  Plan:  {plan-number} of {total-plans} ({plan-name})
  Task:  {task-number} of {total-tasks}

Last Completed
  ➜ {last-completed-description}
  Commit: {commit-hash}

Next Action
  ➜ {next-task-description}

Active Concerns
  {concern-1-or-none}
  {concern-2-or-none}

Progress
  {phase-progress-bar} Phase {N}
  {overall-progress-bar} Overall
```

## Field Rules

- **project-name:** From PROJECT.md "What This Is" heading
- **core-value:** From PROJECT.md, one line
- **Position:** Read from STATE.md current position section
- **Last Completed:** Most recent task commit message and hash
- **Next Action:** First incomplete task from current plan
- **Active Concerns:** From STATE.md blockers/concerns, or "None"
- **Progress bars:** 10-char wide, see vbw-brand.md for format
