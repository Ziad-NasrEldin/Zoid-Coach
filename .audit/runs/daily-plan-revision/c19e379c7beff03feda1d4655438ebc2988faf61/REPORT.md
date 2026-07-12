# Signed daily-plan revision verification

Date: 2026-07-13

Verified commit: `c19e379c7beff03feda1d4655438ebc2988faf61`

Build identity: `zoid-coach-c19e379c7beff03feda1d4655438ebc2988faf61-clean`

Installed application: `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app`

QA root: `/private/tmp/zoid-666-daily-plan-498bca9`

## Result

The installed signed Zoid 666 QA product completed the default Today revision journey end to end through its registered QA helper.

The verifier first exposed and fixed a composition blocker where revision controls existed only in the fallback ledger and were absent from the normal snapshot-backed Today surface.

The corrected surface provides stable accessible controls for moving tasks, marking them optional, deferring or returning them, and recording a blocker reason.

## Visible journey

The signed Today surface opened with three readable planned tasks and 90 planned minutes.

Moving `Review the customer notes` upward made it rank 1 and disabled its Move Up control while enabling Move Up for the former first task.

Marking `Draft the release summary` optional displayed `OPTIONAL - NOT INCLUDED IN CAPACITY OR CALENDAR` and reduced committed capacity from 90 to 60 minutes.

Deferring `Review the customer notes` displayed its exact tomorrow timestamp, changed the action to Return to Today, and reduced committed capacity from 60 to 30 minutes.

Mark Blocked opened a focused sheet that required 3 to 240 characters before Save Blocker became enabled.

Saving `Waiting for final stakeholder approval.` displayed the complete reason beside the blocked task, changed its execution state to Blocked, and showed a successful local-save message.

## Durable and restart proof

The isolated SQLite database recorded `daily-beta`, `daily-alpha`, and `daily-gamma` at ranks 1, 2, and 3.

The same rows durably stored the beta deferral, alpha blocker reason, gamma optional flag, and alpha blocked execution state.

After terminating and relaunching the installed app, the visible Today surface restored the exact order, deferred timestamp, optional label, blocker reason, blocked state, and 30-minute committed capacity.

The relaunch accessibility tree retained every stable revision control and excluded optional and future-deferred tasks from capacity.

## Automated gates

Focused daily-plan revision, migration 35, planning-capacity, scheduler, and Today agent suites passed.

Migration 35 now tolerates both absent and partially upgraded legacy daily-plan tables without losing idempotence.

The release build passed at the pre-notification daily-plan tip, and the authoritative combined commit passed clean signed-QA packaging and deep code-sign verification.

The 42 registry and evidence tests passed.

The full Swift run executed 557 tests and first exposed one incorrect pre-existing classification-rule expectation, which was corrected and passed focused verification.

Subsequent full-run assertions completed, but the Swift Testing helper remained idle in its main run loop and required termination, so this report does not falsely claim a clean full-suite process exit.

## Scenario disposition

`ZC-008-011`, `ZC-008-013`, `ZC-008-014`, and `ZC-008-015` are fully usable end to end.

`ZC-014-007` now has direct signed proof for blocked and deferred visual states, while its broader all-state claim remains Touches remaining until one installed journey also covers paused, active, and completed states together.

