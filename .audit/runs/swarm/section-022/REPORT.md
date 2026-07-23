# Section 022 implementation lane report

## Scope

This lane owns only `ZC-022-001` and `ZC-022-002`.
It does not edit the authoritative tracker, scenario registry, backlog, or active-work ledger.

The worktree fast-forwarded cleanly from `63351c3` to integration baseline `2cba674f8370fc16f9555cdb6f115f18df1f8ced` with `git merge --ff-only codex/full-system` before inspection.

## Per-scenario result

### ZC-022-001 - BLOCKED

The implementation is code complete at the integration baseline.
The active Today surface exposes an away-from-Mac entry action only for an active or paused commitment, binds the entry sheet to the readable task title, persists the bounded entry, and resolves the task identifier back to the readable title in Reviews.

The remaining tracker gap is an installed visual recheck of the readable Reviews title.
The required proof cannot be captured in this lane because the product is a native macOS application while the assigned browser policy permits only Codex's built-in in-app Browser for navigation, inspection, testing, and screenshots.
The in-app Browser controls web pages and cannot inspect the installed native SwiftUI window.
The repository's `Scripts/qa-window-content-probe.swift` and `Scripts/verify-signed-qa-window-content.sh` capture native windows outside that browser, so using them would violate the explicit restriction.

Status: `BLOCKED`, with code complete and installed verification incomplete.

### ZC-022-002 - BLOCKED

The implementation is code complete at the integration baseline.
The active-task sheet provides a bounded duration, completed-time default, optional note, future-time validation, exact success feedback, idempotent persistence, Return and Escape behavior, and separated Actual, Screenwatch-observed, and Away-from-Mac review totals.

This scenario shares the same remaining installed readable-title recheck and the same native-window proof blocker as `ZC-022-001`.

Status: `BLOCKED`, with code complete and installed verification incomplete.

## Files

- Added `.audit/runs/swarm/section-022/REPORT.md` only.
- No production source, tests, shared tracker, registry, backlog, or active-work files were changed.

## Tests and evidence

- Existing candidate and verifier evidence: `.audit/runs/active-offline-work/verifier/REPORT.md`.
- Existing signed journey proved task activation, conditional entry-point visibility, readable entry-sheet title, a persisted 10-minute entry, exact success feedback, restart persistence, and separated review totals.
- Existing focused resolver coverage: `offlineWorkTaskTitleResolverShowsThePlannedTaskTitleAndKeepsAnHonestFallback` in `Tests/ZoidCoachAppTests/ActiveOfflineWorkEntryTests.swift`.
- A fresh `swift test --filter ActiveOfflineWorkEntryTests` was started, but the shared build directory remained contended by many concurrent Swift test processes and did not finish within this lane's bounded run.
- No proof screenshot is claimed because the only permitted browser surface cannot capture the native application window.

## Gaps

- Install the current signed QA package under an isolated QA root.
- Seed or reproduce the active task `Research migration risks`.
- Add away-from-Mac work from the active task.
- Open Reviews and visually confirm the row shows `Task: Research migration risks`, not the raw local task identifier.
- Capture that native installed-app state with an explicitly approved native macOS testing surface.
- Independently verify the exact integrated commit before upgrading either scenario to VERIFIED COMPLETE.

## Integration

Cherry-pick the report commit only if root wants to retain this blocked-lane record.
No product-code integration is required because this lane found the minimum implementation already present on `codex/full-system`.
Root remains responsible for shared tracker and registry decisions.

## Rollback

Revert the report commit to remove this audit record.
There is no product behavior or data migration to roll back.
