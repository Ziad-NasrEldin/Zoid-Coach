# Menu Bar Break And End-Of-Day Verification

## Result

`ZC-023-008` and `ZC-023-010` advance from `Not implemented` to `Touches remaining`.

The signed isolated app started a real planned task through the running QA helper, and Today visibly changed to the active state while preserving the task identity and local tracked-time surface.

The available accessibility harness could not address the macOS status item or open its popover within the capped run, so no menu-extra click is claimed.

## Independent Blocker Fix

The original confirmation captured a task row before the user confirmed End Workday.

If the active task changed while the dialog was open, the old task command would safely no-op in storage but the user would receive no explanation.

Confirmation now refreshes the canonical Today snapshot and applies end-of-day only when the same task is still active.

When the task changed, nothing is paused, the current task is shown, and the menu explains that confirmation became stale.

## Proof

- `MenuBarCoachTests` passed once.
- `AcceptedBreakLifecycleTests` passed once.
- `endWorkdayConfirmationDoesNothingWhenTheActiveTaskChanged` passed after the fix.
- Release build passed once.
- QA package passed once.
- Package signing, LaunchAgent, Mach service, and helper identity verification passed.
- Signed QA installation, helper launch, completed onboarding restore, deterministic local plan restore, and real task start passed.
- Focused canonical-agent proof covers break, countdown state, resume, end-workday pause reason, and database restart persistence.
- `git diff --check` passed.

## Remaining Signed Acceptance

1. Open the actual status-item popover.
2. Start Break and visibly inspect the live countdown.
3. End the break and confirm the same task resumes with tracked time intact.
4. Open End Workday, cancel, and prove no task mutation.
5. Confirm End Workday and inspect the saved-time state.
6. Switch tasks while confirmation is open and visibly prove the stale guard.
7. Restart app and helper, reopen the popover, and prove the end-of-day pause survives.
