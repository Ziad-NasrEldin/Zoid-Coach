# Calendar approval freshness signed acceptance

## Result

The installed signed QA application passed the capped end-to-end Calendar approval freshness journey for `ZC-008-017`, `ZC-009-007`, and `ZC-009-008`.
The run used build `zoid-coach-2f8b7156f6c5c22c80363c5eb611f433dc72bbbf-clean`, application `/private/tmp/zoid-666-calendar-freshness-apps/Zoid 666 QA E2E.app`, and isolated root `/private/tmp/zoid-666-calendar-freshness-qa`.

## Installed user journey

1. The visible Today UI created a 30-minute local task named `Prepare client proposal` and added it to the current plan.
2. Calendar permission was granted and a visible 60-minute external commitment reduced available capacity from 378 to 336 minutes.
3. The approval sheet displayed the exact task, main-objective designation, 30 planned minutes, 336 available minutes, 60 Calendar-busy minutes, and 306 unallocated minutes.
4. The external commitment was cancelled after the review opened without relaunching the application.
5. Confirmation refused the stale review with `NOTHING WAS WRITTEN` and the actionable instruction to review updated availability.
6. SQLite still contained zero action commands, zero plan schedule requests, and the identical one-row 30-minute plan after refusal.
7. `REVIEW UPDATED AVAILABILITY` replaced the preview with 378 available minutes, zero Calendar-busy minutes, and the same reviewed task.
8. Calendar permission was then denied after the refreshed review opened.
9. Confirmation again refused with `NOTHING WAS WRITTEN`, named unavailable Calendar access, and exposed both review-refresh and Source Health actions.
10. SQLite again contained zero action commands, zero plan schedule requests, and the identical one-row 30-minute plan.
11. `OPEN SOURCE HEALTH` reached the visible diagnostics surface, and a refresh showed QA Calendar `ATTENTION`, unavailable permission, the exact conflict-placement impact, and an inspect repair action.
12. Calendar permission was restored, a current approval showed 30 planned minutes against 378 available minutes, and confirmation queued four exact commands.
13. The command ledger reached `succeeded` for one `reconcileCalendarBlock`, one `scheduleNotification`, one `setReminderPriority`, and one `setReminderDueDate` command.
14. The fixture retained one owned Calendar block, one updated Reminder, and one scheduled notification.
15. The visible receipt changed to `CALENDAR CONFIRMED`, stated that four Calendar and Reminder changes were confirmed, and reported `Approved plan confirmed. 4 Calendar changes applied.`
16. The application was relaunched once only after all four commands succeeded, and Today restored the same plan plus the applied four-change receipt without reopening approval.

## Verification

- The one-time rebase onto authoritative root `6c92a59` was clean.
- `swift test --filter CalendarPlanApprovalStateTests` passed 11 tests in one suite after the rebase.
- The single signed QA installation passed package verification, signing validation, exact helper registration, and helper launch from the installed application.
- The cancelled-commitment and denied-permission branches created no commands, writes, or applied receipt.
- The success branch produced four successful command-ledger rows and the durable applied receipt.
- The relaunch receipt screenshot is `04-relaunch-receipt.png`.

## Scope and cleanup

No production application data or production LaunchAgent identity was used.
The tracker and registry are updated only for the three scenarios exercised by this installed journey.
