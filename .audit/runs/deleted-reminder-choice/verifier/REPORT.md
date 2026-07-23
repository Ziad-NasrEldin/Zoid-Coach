# Deleted Reminder choice verifier report

## Verdict

`ZC-021-006` has meaningful installed-app implementation progress, with four acceptance branches still outstanding.
The tracker may advance from `Not implemented` to `Touches remaining`, but not to full implementation.

## Corrected source

- The seven-file candidate was transplanted onto canonical `b61910f34ce3bd32c2165a009b764cd51e76ae0b` and preserved non-destructive migration 46.
- Canonical compatibility required importing `ZoidCoachInfrastructure` in the Reminders view, using the current migration-test helper label, and updating the deleted-row archive query to canonical `source_tasks`, `source_id`, and `source_kind` names.
- The corrected rebased source tip before this report was `cec420c`.

## Focused verification

- The validated original selector executed exactly nine tests and passed 9/9 in 0.084 seconds.
- The correction and migration selector executed exactly three tests and passed 3/3 in 0.046 seconds.
- The 12 tests cover pending decision creation without notes, durable Keep, exact pending-only removal, matching reappearance cleanup, controller retry truthfulness, privacy-safe presentation and identifiers, destructive confirmation copy, rollback on source-deletion failure, and migration 46.

## Signed installed-app proof

- The exact corrected candidate passed package signing, designated-requirement validation, QA XPC writability, helper registration, and runtime heartbeat checks.
- The initial real sync created exactly the three deterministic Reminder source rows and no deleted-choice rows.
- A signed helper fixture update removed the Keep and Remove Reminders while preserving the unrelated Reminder, and native Refresh Reminders created exactly two pending choices while the unrelated source row remained.
- The accessibility tree exposed distinct, collision-free row, Keep, and Remove identifiers for both choices.
- Complete accessibility-tree searches did not expose `Private keep note`, `Private remove note`, `secret.example`, `/keep`, or `/remove`.
- The Remove Local Copy confirmation named only the chosen task and stated that Apple Reminders and other task history would remain unchanged.
- Native Cancel left both choices pending and preserved the unrelated source row.
- Native Keep Local History changed only the matching row to `KEPT IN LOCAL HISTORY`, removed its action buttons, and left the other row pending.

## Remaining acceptance work

- Confirm Remove Local Copy in the signed app and prove that only the selected pending row disappears.
- Reintroduce the kept Reminder through signed real sync and prove that only its matching stale decision clears.
- Complete the final app and helper relaunch proof for the resulting state.
- Exercise a controlled signed post-write refresh failure and the visible retry path, if a safe failure hook is available.

## Cleanup and isolation

- The signed runtime, isolated QA root, and verifier build cache were removed after the bounded run.
- Canonical unrelated dirty files were not modified during verification.
