---
name: vbw-release
description: Release a new VBW version - tests on both shells, the real-user scenarios, the version bump and changelog, CI, and publishing only on the owner's word.
---

# Releasing VBW

Every step runs; a failure stops the release until its root cause is fixed.

1. **Tests:** CI is the gate (owner decision, 2026-10-24). Locally, run the
   test files of the changed area under macOS `/bin/bash` 3.2
   (`PATH="/bin:$PATH" bats tests/...`) before pushing; a full local run is not
   required. CI runs the release run (`tools/test.sh --release`, in shards: the
   proof's run plus both benchmarks and the timed files) under macOS bash 3.2,
   bash 5 and Linux on the pull request. The macOS shards and the manifest
   validation must pass before the merge; a Linux-only failure that cannot affect
   macOS goes to the next batch. `tools/test-linux.sh` stays for chasing a
   Linux-only failure.
2. **Real-user scenarios:** `bash tools/l3-suite.sh SCENARIO...` (the real
   Claude Code TUI, driven as a user; each scenario costs API credits). Run only
   the scenarios of the area the release changed, plus `greenfield` when the
   release touches the core loop (the router, `vbw next`, a workflow, the proof
   or QA). The full suite runs before the 2.1 launch. The release record names
   the scenarios run and those not run. Every check must pass.
3. **Version:** `bash tools/bump-version.sh --set X.Y.Z` (all five version files),
   then a `plugin/CHANGELOG.md` entry written for users: what they can do now,
   what was fixed, anything they must do. Every build a user is meant to receive
   gets a new version: Claude Code updates a plugin only when its version changes.
4. **Claude Code changes:** read the Claude Code changelog for every version
   since the last release and check what touches plugins, hooks, mods, skills,
   the status line or settings (a maintainer step, never part of VBW).
5. **Docs:** `README.md` and `docs/` match what was built (commands, settings,
   requirements).
6. **Publish, only on the owner's word:** push the branch and open the pull
   request. Wait for CI: merge only when the macOS shards and the manifest
   validation pass (the two VBW 1-era checks "Linked Issue Check" and "QA Review
   Evidence" fail on every maintainer PR until they are retired). Then tag the
   merged commit and publish the release.
7. **Verify the update path:** in a throwaway `CLAUDE_CONFIG_DIR`, install the
   previous release, then update with `claude plugin marketplace update` and
   `claude plugin update`; the new version must be installed and load.
8. **Record** the release in the progress log with its evidence levels and a
   Not tested list.
