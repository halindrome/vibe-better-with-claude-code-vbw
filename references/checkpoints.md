# VBW Checkpoint Protocol

Rules for pausing and resuming VBW execution sessions.

## When to Checkpoint

- End of a plan execution (automatic)
- End of a phase (automatic)
- User-requested pause (`/vbw pause`)
- Authentication gate (blocked on credentials)
- Architectural decision needed (deviation Rule 4)

## What to Save

At each checkpoint, persist:

- **Position:** Current phase, plan, and task number
- **Pending work:** Tasks remaining in current plan
- **Active decisions:** Unresolved choices awaiting user input
- **Blocker status:** What is blocking continuation
- **Completed commits:** Hashes of all task commits so far

## Where to Save

| Data             | Location   | Purpose                        |
|------------------|------------|--------------------------------|
| Position/status  | STATE.md   | Dashboard for resume discovery |
| Persistent facts | CLAUDE.md  | Survives session boundaries    |
| Plan progress    | SUMMARY.md | Partial summary if mid-plan    |

## How to Resume

1. `/vbw resume` reads STATE.md for current position
2. Presents structured continuation summary (see continuation-format.md)
3. Verifies previous commits exist in git history
4. Resumes from the exact task where execution stopped
5. Completed tasks are never re-executed
