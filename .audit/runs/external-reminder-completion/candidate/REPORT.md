# External Reminder completion candidate report

## Scope

This candidate implements `ZC-021-002` without changing the authoritative tracker, registry, Lavish report, runtime fixtures, or app-shell startup code.

## User behavior

When a synchronized Apple Reminder for the active task becomes completed, Zoid 666 closes the active task through the canonical completion transition.
Today preserves the row as completed and states `Ended because the Apple Reminder was completed` instead of silently removing it.
The stopped elapsed time, completion reason, and completed state survive repeated refreshes and a new agent instance.
The next planned task remains available.
The external completion records Reminder-sourced task history once and does not enqueue a redundant Reminder completion command.

## Automated proof

- `swift test --filter "externallyCompletingActiveAppleReminderEndsSessionWithDurableReason|externalReminderCompletionReasonIsExplicitForTheUser"` passed with two tests.
- `swift build -c release` passed.
- `git diff --check` passed.

The focused journey creates two Reminder-backed plan rows, starts a bounded sprint, synchronizes the active Reminder as completed, and refreshes Today after five minutes.
It verifies that no task remains active, the completed row carries the explicit external-completion reason and stopped elapsed time, the next task remains visible, no redundant outbox command exists, and Reminder-sourced completion history is recorded at the transition time.
It then verifies that a repeated refresh does not change the completion time or add tracked time and that a new agent instance restores the same completed explanation.

## Baseline note

The existing `deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` regression throws `TaskExecutionStoreError.write` on untouched authoritative commit `ba6466a` and on this candidate.
That independent baseline failure is not caused by `ZC-021-002` and remains outside this lane.

## Remaining acceptance

A fresh verifier must complete an active Reminder through Apple Reminders while the signed installed app and helper are running.
The verifier must confirm the visible Today reason, stopped timer, remaining-task usability, refresh and relaunch persistence, one completion-history event, and absence of a redundant completion request before the authoritative tracker advances.
