# Calendar Approval Receipt Verification

## Result

The receipt implementation is accepted as a durable foundation, and the tracker remains conservative at `Touches remaining` for `ZC-008-017`, `ZC-008-018`, and `ZC-058-005`.

The installed signed app visibly presented the exact reviewed task, main-objective label, 30-minute estimate, configured capacity fallback, and explicit Confirm and Write boundary.

The isolated Calendar fixture was not connected, so confirmation truthfully produced `NOTHING WAS WRITTEN`, retained the reviewed plan, exposed Source Health repair, and created no action commands.

Because no commands were accepted, this run does not claim the pending receipt, relaunch reconciliation, confirmed receipt, or installed terminal-failure retry journey.

## Independent Blocker Fix

Inspection found that a terminal receipt only offered Recheck even though reconciliation correctly stops after terminal failure.

The verifier added `RETRY FAILED CHANGES`, which sends only the exact failed command identifiers through XPC and changes their existing outbox rows back to pending.

The retry path rejects missing, pending, succeeded, cancelled, or otherwise ineligible identities before mutating any command, so it cannot silently create replacement commands or duplicate successful writes.

If the retry request itself fails, the same failed receipt identity and repair language are restored.

## Proof

- `CalendarPlanApprovalStateTests` passed once on the rebased candidate.
- `terminalFailureRetriesExactReceiptCommands` passed after the blocker fix.
- The release build passed once.
- The QA package passed once.
- Package signing, LaunchAgent, Mach service, and helper identity verification passed.
- Signed QA installation and launch passed with isolated runtime and install roots.
- The visible review and atomic-refusal journey passed.
- `git diff --check` passed.

## Remaining Signed Acceptance

1. Connect the isolated Calendar fixture before confirmation.
2. Confirm once and record exact pending receipt command identifiers.
3. Relaunch before completion and prove the closed receipt restores without adding outbox rows.
4. Complete the exact commands and prove the receipt becomes confirmed after refresh and another relaunch.
5. Force one terminal failure, repair the fixture, choose Retry Failed Changes, and prove the same outbox row succeeds without replacement.
