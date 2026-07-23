# Today end-workday acceptance report

## Identity

- Scenario: `ZC-013-010` - End the workday from the dashboard.
- Authoritative baseline: `d618680`.
- Feature commit: `52eda03`.
- Verifier fix and signed build: `848dd365f1f2c751f64f8cecdb5fef748f2b8702`.
- Installed app: `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app`.
- Isolated QA root: `/private/tmp/zoid-666-today-end-workday-qa`.

## Automated acceptance

All three focused `DashboardEndWorkdayFlowTests` passed.
All nineteen affected `EndWorkdayReviewControllerTests` and `TodayDashboardAgentTests` passed.
The authoritative predecessor changed only evidence, tracker, registry, and Lavish files, so the affected seams did not require a second run after the one-time rebase.
The release signed package and exact rebased signed install passed with coherent app, LaunchAgent, Mach service, and signing identities.

## Verifier fix

The candidate originally claimed the active task was unchanged after an unconfirmed or malformed agent result.
That was not knowable if transport failed after a durable mutation.
The verifier changed both failure messages to state only that Zoid 666 could not confirm the result and to direct the user to refreshed Today state and Agent source health.

## Signed end-user acceptance

With no active task, Today did not expose an end-workday action.
After the end user started `Close the quarterly plan`, Today displayed a fixed `End today's workday and open the review` action.
Its accessibility hint explicitly stated that tracked time would be preserved and the task would not be marked complete.
The destructive confirmation named `Close the quarterly plan`, explained the fresh recheck, and repeated the preserve-time and not-complete guarantees.
Cancel dismissed the confirmation, kept the task active, and kept the user on Today.
While a confirmation remained open, the task was paused through the signed app keyboard command.
Confirming that stale dialog performed no second mutation, stayed on Today, and displayed the exact stale-active-task explanation.
After the helper was removed, confirmation stayed on Today, retained the active task, and displayed the honest could-not-confirm recovery message.
The signed app repaired and re-registered its helper, and an app restart restored the same active task before success.
After final confirmation, the app navigated to Reviews only after the agent returned a paused `endingWorkday` result.
Reviews showed `Close the quarterly plan` as unfinished and open, showed no completed task record, and retained observed active-task time.
After both the helper and app restarted, Today restored `Paused at the end of the workday`, preserved three tracked minutes, exposed Resume, and still did not mark the task complete.

## Result

`ZC-013-010` is fully usable end to end in the signed installed app.
