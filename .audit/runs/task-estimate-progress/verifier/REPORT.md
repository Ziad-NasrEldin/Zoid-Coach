# Task Estimate Progress Verification

## Decision

ZC-018-001, ZC-018-003, and ZC-037-004 are fully implemented and visibly usable end to end in the signed QA product.

## Integrated lineage

The authoritative verification baseline was clean root commit `49fe140` on `codex/full-system`.
The integrated task-progress implementation and verifier fixes are commits `3a61b77`, `190c5f7`, and `bfddcac` in the authoritative lineage.
The signed QA application identified itself as Zoid 666 Build 8 and used isolated QA root `/private/tmp/zoid-task-estimate-qa`.
The package passed signing, designated-requirement, LaunchAgent, exact-helper, and installed-runtime checks before the visible journey began.

## Focused verification

`swift test --filter TaskEstimateProgress` passed all seven focused tests on the final integrated root.
The suite covers not-started, remaining, estimate-reached, over-estimate, bounded geometry, invalid and extreme values, active elapsed advancement, and canonical SQLite restart recovery.
`python3 Scripts/scenario_registry.py validate` confirmed all 666 scenarios with no tracker drift before the status update.

## Signed installed journey

The verifier left incomplete onboarding through the visible `EXIT FOR NOW` action and opened Today.
The verifier created a local task named `Verify estimate progress`, reduced its visible estimate to 5 minutes, added it to today's plan, and started it through `BEGIN FOCUS`.
The active focus card visibly showed the task title and the accessible progress summary `0 minutes tracked of 5 estimated, not started` at stable identifier `today.focus.estimate-progress`.
The verifier opened the labelled Pause menu and chose `Take a break`.
Today visibly changed to `PAUSED FOR A BREAK`, retained the title, estimate, Resume and Complete controls, and kept the factual progress summary.
The app process was terminated and relaunched from the installed signed application.
After returning to Today, the same task remained paused for a break with the same 5-minute estimate and controls, proving canonical recovery rather than view-local state.
To reach the over-estimate boundary without waiting seven wall-clock minutes, the verifier adjusted only the isolated QA activity interval to a completed seven-minute canonical interval and relaunched the installed application again.
Today then visibly and accessibly reported `7 minutes tracked of 5 estimated, 2 min over estimate` while the task remained paused and resumable.

## Acceptance boundaries

The displayed language is factual and does not describe the user as late, failing, or unproductive.
The progress bar remains visually bounded while the accessible and textual percentage model can truthfully exceed 100 percent.
Ready, completed, blocked, deferred, and rescheduled rows do not receive a misleading live progress surface.
Active progress advances minute by minute from the canonical snapshot, while paused progress stays stable.
