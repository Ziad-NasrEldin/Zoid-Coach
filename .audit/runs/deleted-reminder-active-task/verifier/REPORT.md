# Deleted active Reminder verification

## Result

`ZC-021-005` advances from Not implemented to Touches remaining.
The implementation and focused persistence journey pass, but the complete installed end-user deletion journey remains unverified.

## Automated proof

The focused `deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` test passed after rebasing onto authoritative commit `43f3b96`.
The complete `TodayDashboardAgentTests` suite passed.
One release package completed successfully.
The focused journey proves one pause transition, a closed interval, a paused sprint, five stopped elapsed minutes across repeated refresh and restart, one retained deleted row, one usable remaining row, and final orphan dismissal through completion.

## Signed evidence

The signed QA app and helper installed under isolated runtime and install roots.
The verifier used the existing QA control request path and did not access or mutate the user's real Apple Reminders.
The first malformed permission dictionary failed closed in the processing file and did not mutate fixture state.
The corrected fixture encoded the permission dictionary using Swift's alternating key-value array representation.
The signed Reminders onboarding step visibly reported Healthy with two fixture Reminders available.
Native Accessibility activated Reminders access, included the Work list, continued through Screenwatch and Notifications, and reached App Inventory.
Pixel evidence captured the connected Healthy Reminders state.

## Remaining acceptance

The runtime cap expired before an active task could be started and its fixture Reminder deleted externally.
The installed Today reason, stopped interval and sprint, restart singularity, remaining-row usability, and final orphan completion therefore remain unclaimed.
System Events descendant counts were not used as a visibility oracle.
The installed app was removed, the QA LaunchAgent was unregistered, and the isolated runtime was cleaned before the lease was released.
