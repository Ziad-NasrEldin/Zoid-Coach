# Deleted active Reminder candidate report

## Scope

This candidate implements `ZC-021-005` without changing the authoritative tracker, registry, Lavish report, runtime fixtures, or app-shell startup code.

## User behavior

When the current task disappears from the synchronized Apple Reminders source, Zoid 666 closes its active interval and pauses its sprint in one transaction.
Today preserves the row with the title and plan context the user already saw.
The row states `Paused because the Apple Reminder was deleted` instead of silently disappearing.
Later refreshes and a new agent instance preserve the same stopped elapsed time.
Completing the orphaned row removes it from Today and leaves the remaining planned task available.

## Automated proof

- `swift test --filter deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` passed.
- `swift test --filter TodayDashboardAgentTests` passed.
- `swift build -c release` passed.

The focused journey creates two Reminder-backed plan rows, starts a bounded sprint, synchronizes a source snapshot that omits the active Reminder, and refreshes Today.
It verifies that there is no active task, the deleted row is paused with five stopped minutes and a paused sprint, the next task remains visible, a repeated refresh does not add time or duplicate the row, restart preserves the reason and elapsed time, and completion dismisses the orphaned row.

## Remaining acceptance

A fresh verifier must delete an active Reminder through Apple Reminders while the signed installed app and helper are running.
The verifier must confirm the visible Today reason, stopped timer, paused sprint, remaining-task usability, restart persistence, and final dismissal before the authoritative tracker advances.
