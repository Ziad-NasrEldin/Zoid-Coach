# Blocked-task replan verifier report

## Scope

- Scenario: `ZC-019-010` - Replan after an important task becomes blocked.
- Authoritative baseline: `e614916`.
- Rebased implementation: `150e800`.
- Signed build identity: `5f31703`.
- Installed app: `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app`.
- Isolated QA root: `/private/tmp/zoid-666-blocked-task-replan-qa`.

## Automated verification

The focused `TodayDashboardAgentTests` suite passed before the one-time rebase.
The authoritative predecessor changed only evidence, tracker, registry, and Lavish files, so no affected product seam required a second run after rebasing.
The focused proof covers blocker persistence, plan-order replacement selection, main-objective promotion, recommendation refresh, agent reconstruction, undo revision restoration, and the no-replacement edge case.
The release signed install passed with coherent app, LaunchAgent, Mach service, and signing identities.

## Signed end-user states observed

The installed app exited paused onboarding into Today.
The end user created `Blocked primary objective` and `Named replacement task` as local tasks with `Add to today's plan` enabled.
Today visibly presented `Blocked primary objective` as the main objective and `Named replacement task` as the next planned task.
The end user started `Blocked primary objective` and Today visibly changed it to the active commitment.
The active-task Pause menu visibly offered `Task is blocked`.
The task row visibly offered `Mark blocked` while the named replacement remained ready.

## Acceptance boundary

Computer Use repeatedly lost the app window when activating the blocker action, including through the menu and the visible task-row control.
The process and helper remained running, and reopening the window restored the same active task and plan, but the ten-minute signed UI cap expired before blocker submission, named replacement promotion, undo, restart persistence, or the no-candidate UI path could be observed.
This is an automation acceptance blocker rather than evidence of a product mutation failure.
The scenario therefore moves from `Not implemented` to `Touches remaining`, not `Fully implemented`.

## Scenario correction

`ZC-034-011` remains `Barely started` because it is specifically the coaching-response `markBlocked` action.
The task-row blocker and blocked-task replan implementation do not connect that coaching action to a blocker-reason flow.

## Remaining acceptance

Run one successful signed click-through that submits the blocker reason, observes `Named replacement task` as both main objective and next recommendation, exercises undo, verifies app and helper restart persistence, and repeats with no eligible replacement.
