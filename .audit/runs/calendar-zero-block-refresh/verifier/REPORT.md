# ZC-046-009 Calendar Zero-Block Refresh Verification

## Verdict

The stale zero-block defect is fixed and the Calendar-denied local-plan journey is now usable end to end.
The scenario remains **Touches remaining** because the repaired Calendar journey exposed a separate receipt-label defect when notification delivery is denied.

## Revision boundary

- The exact signed source revision was `73a6aaef5bf151c537ec7c7b8820939f0b927487` on canonical base `dd5737cf9b6a47791a1ddfbb8dac52a6be943a93`.
- The accepted source patch retained stable patch identifier `7528e9a8deeee23cb634821a73bbdb83f38a1b2b`.
- The source patch changed only `TodayPlanPresentation.swift`, `TodayDashboardCommandOverview.swift`, and `TodayPlanPresentationTests.swift`.
- `AppModel.swift`, the scenario tracker, the registry, and the Lavish audit were untouched during signed verification.

## Deterministic proof

- `swift test --filter TodayPlanPresentationTests` passed 3 tests with zero failures.
- The suite proves that a new live plan replaces a stale empty helper snapshot, locally removed rows do not linger, and live plan fields replace stale plan fields without losing authoritative execution state.
- `git diff --check` passed.

## Signed Calendar-denied journey

- The clean release QA package passed package verification, signing, LaunchAgent registration, Mach-service validation, and writable XPC validation.
- The isolated app started with one Reminder named `Protect the local approved plan`, Calendar permission denied, and no Calendar commitments.
- The initial Today surface truthfully showed `0 PLANNED BLOCKS`, `0 MIN PLANNED`, and configured-work-window fallback copy.
- Adding the Reminder to Today immediately changed the visible Day Map to `1 PLANNED BLOCK` before the helper snapshot refreshed.
- Choosing a 45-minute estimate immediately changed capacity to `45 MIN PLANNED / 378 MIN AVAILABLE`.
- The approval sheet showed the exact task, configured-work-window fallback copy, and `USE PLAN LOCALLY` instead of an external-write action.
- Closing the sheet and relaunching produced no receipt and did not replay approval.
- Reopening and choosing `USE PLAN LOCALLY` showed `LOCAL PLAN READY`, the exact main task, the 45-minute estimate, and explicit zero Calendar and Reminder writes.
- The isolated database contained exactly one plan row, no Calendar plan operation, and no Calendar or Reminder action commands.
- The fixture still contained zero Calendar commitments.
- Restarting both app and helper restored the exact plan and local-only receipt without reopening the approval modal.
- `REVIEW RECEIPT` restored the exact main task and 45-minute estimate.

## Calendar repair follow-up

- Granting Calendar access in the isolated fixture and restarting both app and helper changed the approval sheet to the normal conflict-aware `CONFIRM AND WRITE` path.
- Confirming once created exactly four command identities and one completed Calendar operation containing the same four identities.
- The isolated fixture contained exactly one owned Calendar commitment, one Reminder, and the database retained exactly one daily-plan row.
- The Calendar block, Reminder priority, and Reminder due-date commands succeeded without duplicating the local plan or fixture records.
- Notification permission intentionally remained denied, so the related notification command terminal-failed.
- After relaunch, the receipt summary incorrectly said `Approved plan kept locally. 1 Calendar change needs repair.` even though Calendar and Reminder mutations had succeeded and only notification delivery failed.
- The screenshot `final-after-repair.png` records that truthful remaining acceptance gap.

## Cleanup

- The QA app and helper were stopped and unregistered.
- The isolated install, database, fixture, manifest, and temporary runtime roots were removed.
- No production application data, Calendar data, Reminder data, or notification state was used.

## Required follow-up

Receipt reconciliation must distinguish a notification delivery failure from a Calendar or Reminder write failure.
The repaired journey should say that the plan was written successfully and separately identify notification delivery as unavailable.
