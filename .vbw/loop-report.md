# Loop report

Started 2026-10-13T16:35:58Z. State: running (an item still in progress shows as in progress).

## Shipped
- T128 Machine-wide limit (owner, 2026-10-12 09:40): VBW as a whole never takes more than about three quarters of the machine's cores, however many projects, sessions and runs are proving at once: one shared budget per machine (a slot store in the user's Claude config folder, each unit of a proof or fix done takes a slot, a run that finds none waits its turn), so runs take turns instead of fighting (today a 12-minute fix done took 87 under four concurrent runs). Same tests, same results, no thrash; the check_jobs setting stays as a per-run cap below it. Goes with T127 (one fix done per fix round). First item after 2.0.34, before the loop (M26, R181): 9aacd2ca fix(P131.1): tell a limit lost mid-run once at the end, wait unbounded for a live lock owner; 08972554 docs(P131.3): limit lost mid-run, lock wait; 15e3ce6b feat(P131.1): say when a run waited for other VBW runs; 08f623f4 docs(P131.3): the computer-wide limit; 09a8c7d6 feat(P130.2): the shared slot store, every unit takes a turn across the computer; 0e96c403 feat(P131.2): vbw config shows the computer-wide limit; 10ac396a feat(P130.1): vbw_machine_limit, three quarters of the cores; fc1110a2 feat(P130.1): one vbw_claude_dir, used by the status line settings lookup

## Parked
none

## Waiting for you
no skipped [human] requirement
the loop is still running

## Cost
Loop total: $1041.25 (651086 in, 311 out)
- T128 (shipped): $1041.25 (651086 in, 311 out)
