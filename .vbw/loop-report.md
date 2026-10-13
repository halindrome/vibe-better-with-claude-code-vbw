# Loop report

Started 2026-10-13T16:35:58Z. State: running (an item still in progress shows as in progress).

## Shipped
- T128 Machine-wide limit (owner, 2026-10-12 09:40): VBW as a whole never takes more than about three quarters of the machine's cores, however many projects, sessions and runs are proving at once: one shared budget per machine (a slot store in the user's Claude config folder, each unit of a proof or fix done takes a slot, a run that finds none waits its turn), so runs take turns instead of fighting (today a 12-minute fix done took 87 under four concurrent runs). Same tests, same results, no thrash; the check_jobs setting stays as a per-run cap below it. Goes with T127 (one fix done per fix round). First item after 2.0.34, before the loop (M26, R181): 9aacd2ca fix(P131.1): tell a limit lost mid-run once at the end, wait unbounded for a live lock owner; 08972554 docs(P131.3): limit lost mid-run, lock wait; 15e3ce6b feat(P131.1): say when a run waited for other VBW runs; 08f623f4 docs(P131.3): the computer-wide limit; 09a8c7d6 feat(P130.2): the shared slot store, every unit takes a turn across the computer; 0e96c403 feat(P131.2): vbw config shows the computer-wide limit; 10ac396a feat(P130.1): vbw_machine_limit, three quarters of the cores; fc1110a2 feat(P130.1): one vbw_claude_dir, used by the status line settings lookup
- T127 Several vbw fix done runs at once slow each other down (2026-10-12: three in parallel plus another session's run took a 12-minute run to 87 minutes). The fixing workflow has every Dev run its own fix done, so a round with several groups already runs several at once. Decide: the kernel serialises fix done runs (one proof lock per clone, the later ones wait and reuse), or the workflow runs one fix done for all groups at the end; measure first (M27, R182): 87fb297a fix(P132.2): complete follows the plan: no open-fix term without a session; e68fd43a test(P132.4): measure the fix round after the change; 747c437e docs(P132.2): Dev and Lead agents on the round's one vbw fix done; 53fce21e feat(P132.2): fix round runs one vbw fix done after every Dev returns; e38d308e docs(P132.3): explain the new fix round order in the user docs; 6dbeba63 test(P132.1): fix round measured before the change; 2f68dee6 feat(P132.1): measuring script for a fix round
- T130 Stale proof copies: a process killed outright leaves its .vbw/runtime/proof.* copy (13 MB seen 2026-10-12 05:26 from a killed duplicate fix done); the next proof removes copies whose owner process is gone (record the owner pid in the copy folder, as the gate's mutex does), with a test. Part of the machine-wide limit milestone (T128) (M28, R183): 3b23ef9a feat(P133.1): name proof copies after their owner and sweep dead ones

## Parked
none

## Waiting for you
no skipped [human] requirement
the loop is still running

## Cost
Loop total: $1061.32 (714105 in, 279 out)
- T128 (shipped): $1041.25 (651086 in, 311 out)
- T127 (shipped): $15.48 (50374 in, 75 out)
- T130 (shipped): $1059.97 (710023 in, 85 out)
