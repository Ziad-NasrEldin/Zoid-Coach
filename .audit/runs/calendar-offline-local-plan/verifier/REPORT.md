# ZC-046-009 Calendar Offline Local-Plan Verification

## Current verdict

The canonical scenario remains unchecked at **Touches remaining**.

The implementation and deterministic verification now cover the local-only plan boundary, durable pending receipts, partial command reconciliation, and one-shot exact retry without claiming an external write before confirmation.

A signed installed-app journey with Calendar unavailable, recovery, retry, and relaunch is still required before any promotion to **Fully implemented**.

## Revision boundary

- Authoritative baseline: `69fd38fcbb4969063abe1532d5dbaae9ad733cd8`.
- Verification branch: `codex/verify-calendar-offline-local-plan`.
- Canonical tracker, registry, Lavish audit, backlog, runtime fixtures, mutation stores, and notification QA seams were not edited.

## Existing end-user behavior verified in source and tests

- When Calendar availability cannot be read, the preview uses configured work-window capacity and offers `USE PLAN LOCALLY` instead of `CONFIRM AND WRITE`.
- The action's accessibility hint states that the reviewed plan is approved without requesting Calendar or Reminder changes.
- Local approval produces `LOCAL PLAN READY` and states that the plan remains on this Mac.
- The local receipt contains no command identifiers, reports zero writes, restores the exact reviewed tasks, and does not reopen the approval modal after relaunch.
- A Calendar-backed review cannot silently downgrade to local-only approval.
- Pending, failed, and applied panels distinguish queued work from confirmed work and do not claim Calendar blocks exist before the local agent reports success.
- Failed copy keeps the approved plan local, directs the user to Source Health, and provides a stable accessibility identifier for retry.

## Independent repair

The verifier found that a two-command write with one success and one terminal failure forgot the original total when the failed command was retried.

After recovery, the UI could therefore report one applied command even though the approved write contained two commands.

The state now preserves the original command total across failure, receipt restore, retry-request failure, and successful retry.

Only the failed command identity is returned for retry, and a second retry request is suppressed while that exact command is pending.

The verifier also found that a mix of final failure and still-retrying results could prematurely leave pending state and omit an in-flight command.

Reconciliation now remains pending until every currently tracked command has reached success, terminal failure, or cancellation.

## Deterministic proof

- The baseline focused suite passed 13 tests before the repair.
- The repaired focused suite `swift test --filter CalendarPlanApprovalState` passed 15 tests with zero failures.
- A partial success plus retryable failure remains pending, survives receipt restoration, and applies only after both exact commands succeed.
- A partial terminal failure restores with only the failed command eligible for retry while retaining the original two-command total.
- The first retry request returns the exact failed identity and the duplicate request returns no identities while pending.
- A successful retry transitions to applied with the truthful original total of two commands.
- `swift build -c release` completed successfully.
- `git diff --check` passed.

## Required signed acceptance

1. Create an approved local plan while Calendar access is unavailable or the local Calendar service is offline.
2. Verify the preview names configured-work-window capacity, offers `USE PLAN LOCALLY`, and never claims external writes.
3. Approve locally and verify the exact plan, local-only state, zero commands, privacy-safe copy, and keyboard or accessibility reachability.
4. Restart the app and helper and verify the same plan and receipt without an approval replay.
5. Exercise an external-write approval with one successful command and one recoverable Calendar failure.
6. Restart while the failed command remains pending and verify the pending state remains truthful.
7. Restore Calendar access, retry once, verify only the failed identity is submitted, and prove both commands are ultimately represented in the confirmed total without duplicate events or Reminder mutations.

Until this installed sequence is captured, the recommended status remains **Touches remaining**.
