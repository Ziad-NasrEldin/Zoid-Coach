# Completed Task History Verification Evidence

## Scope

- Verified tip: `35781320e8d7b18adc5ba224112daba1c0f03776`.
- Integrated baseline: `6343d0b`.
- Primary scenarios: `ZC-006-014` and `ZC-006-015`.
- Supporting scenarios cover immediate task-list removal, durable title and source snapshots, last-pause context, per-day deduplication, restart persistence, source deletion tolerance, accessibility, privacy, and honest failure states.

## End-user result

- Completing a local task removes it from both the planned and unplanned Today inventories immediately.
- Completing a Reminder-backed task also removes it from Today immediately while the durable Apple Reminders outbox write is still pending.
- Reviews shows a day-neutral `COMPLETED TASKS` section for the selected day.
- Each completed row exposes the readable title, completion time, source, and latest factual pause reason when one exists.
- The stored title and source survive restart and do not depend on the source task continuing to exist.
- Repeated completion records for the same task and day render one latest row.
- The section never exposes window titles, URLs, screenshots, or other raw behavior evidence.
- Empty and load-failure states remain explicit and actionable through the existing Daily Review surface.

## Automated proof

- Focused `TaskHistoryStore`, `DailyReview`, `TodayDashboardAgent`, and migration tests passed after rebasing onto the Calendar and manual-local-task tip.
- A new focused test proves a Reminder-backed task disappears from Today while its Apple Reminders source write remains pending and its readable history is already available.
- Existing lifecycle expectations now enforce absence from Today and preservation of the last pause reason in completed history.
- All 42 Python registry, package, identity, and evidence tests passed.
- The authoritative registry validated exactly 666 scenarios with no tracker drift before the status update.
- The release build passed.
- Parallel and serial full Swift invocations were stopped after the runner became idle without producing further test output.
- No broad completion claim relies on those inconclusive full-run attempts.

## Signed QA proof

- The exact signed QA package installed at `/private/tmp/zoid-completed-history-apps/Zoid 666 QA E2E.app` with isolated data at `/private/tmp/zoid-completed-history-qa`.
- Package verification passed deep signing, designated-requirement, LaunchAgent, Mach-service, and QA-isolation checks.
- The packaged XPC probe created a real local task, replayed creation idempotently, restarted the helper, started the task, completed it, restarted again, verified durable history, and verified that no Apple Reminders mutation was queued.
- The installed Today UI visibly showed no active or available copy of the completed task.
- The installed Reviews UI visibly showed `COMPLETED TASKS`, `Verify the signed local task journey`, its completion time, and `Local task`.
- After killing and relaunching the installed app, Today still excluded the task and Reviews showed the same completed row.
- Accessibility exposed the Reviews surface, reload action, completed section, readable row content, empty states, and privacy explanation without exposing raw telemetry.

## Conservative tracker boundary

- `ZC-006-014` and `ZC-006-015` qualify as fully implemented from the signed end-to-end journey.
- The combined complete-task-to-history journey and the last-pause-in-review scenario also qualify because both the UI path and durable evidence are now present.
- External Reminder completion and source-write failure recovery remain below fully implemented because those distinct live failure journeys were not exercised here.
