# ZC-008-016 independent acceptance report

## Scope and isolation

This acceptance started from authoritative `codex/full-system` commit `27f034a779aef110a93942a51b25d71643a0c0d3` in the fresh worktree `/private/tmp/zoid-666-accept-gaming-unlock` on branch `codex/accept-gaming-unlock`.
The repair commit `5b33f68e1fe33089f397f6bb44a4a6b3f20f64c8` was transplanted as `9b54c7f`.
The prior signed-verifier report commit `8195688929b6393d1c2e28bf499ac82d7765a782` was transplanted as `5b06313` after resolving its report-file modify/delete conflict by retaining the requested report.
The repair changes only `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift` and `Tests/ZoidCoachAppTests/GamingUnlockConditionPresentationTests.swift`.
No tracker, registry, Lavish, mutation operation-key, or Send Test file is owned by this lane.

## Independent source review

The end-user Today path renders `TodayPlanTaskRow` from `TodayDashboardCommandOverview.dayMap` and now passes the current `GamingStatus` into every reachable planned-task row.
The current main objective alone shows `GAMING UNLOCK - COMPLETE THIS TASK FOR N MIN` while a reward is locked.
Every non-main row exposes stable identifier `today.plan.<task-id>.make-main`.
When a reward is locked, that button is titled `MAKE MAIN + GAMING UNLOCK`, explains that both the main objective and one-time reward condition move, and opens an explicit confirmation instead of mutating immediately.
Cancel performs no action.
`Move unlock condition` invokes the existing `AppModel.setMainObjective` path.
That path maps every plan entry in one operation, makes only the selected task main, and persists the complete plan through the existing serialized XPC persistence queue.
When gaming budgeting is disabled or the reward has already been earned, the same reachable row preserves the ordinary direct `MAKE MAIN` behavior without unlock wording or confirmation.
The control discloses only task title and configured reward minutes, so it introduces no additional sensitive telemetry or capture disclosure.
The visible button title, consequence-first accessibility hint, stable identifier, and native alert roles provide the required accessible interaction surface.
The completion path checks the durable current snapshot's main-objective flag before writing the reward ledger.
The reward ledger has a unique day-and-policy constraint, which is the canonical exactly-once boundary.

The signed traversal corrected one source-review assumption.
`TodayDashboardCommandOverview.isMainObjective(_:)` reads `TodayTaskRow.isMainObjective` from the last agent snapshot instead of the immediately updated `AppModel.dailyPlan` entry.
The confirmed mutation therefore persists correctly but leaves the visible unlock condition on the former main row until the next snapshot refresh or relaunch.

## Pending acceptance gates

The focused red-capable command is `swift test --filter GamingUnlockConditionPresentation`.
It exercises the exact locked label, non-main action, confirmation gating, accessibility consequence, and ordinary fallback state.
The focused command passed with process exit 0 on 14 July 2026.
The selected Swift Testing run executed both `Plan gaming unlock condition` and `Reachable Today gaming unlock control` without a failure.
The single `swift build -c release` invocation passed with process exit 0 and produced executable `.build/release/ZoidCoach`.
The build lease ended with 5.0 GiB free on the Data volume.
## Signed native acceptance

The isolated signed QA package installed at `/private/tmp/zoid-666-gaming-accept-install/Zoid 666 QA E2E.app` with QA root `/private/tmp/zoid-666-gaming-accept-qa`.
The native Accessibility probe proved a visible 1180 by 760 Today window with 117 content nodes.
The drafted two-task plan displayed `GAMING UNLOCK - COMPLETE THIS TASK FOR 15 MIN` on `qa-gaming-new` and enabled `today.plan.qa-gaming-old.make-main` with exact value `MAKE MAIN + GAMING UNLOCK`.
The action help was `Moves both today's main objective and the one-time gaming reward condition to this task.`
The alert exposed exact title `Move main objective and gaming unlock?`, named `Complete old objective first`, disclosed the 15-minute consequence, and exposed `Cancel` and `Move unlock condition`.
Cancel left raw `daily_plan_entries` unchanged with `qa-gaming-new` as the only main objective.
Confirm persisted `qa-gaming-old` as the only main objective and `qa-gaming-new` as non-main.
Immediately after confirm, however, native AX still placed the unlock label on `qa-gaming-new` and still offered the move action on `qa-gaming-old`.
This is the remaining end-user defect.
After relaunch, native AX correctly placed the unlock label on `qa-gaming-old` and the move action on `qa-gaming-new`, proving durable single-main persistence.
Completing the former main `qa-gaming-new` left `gaming_reward_ledger` at zero rows and the visible breakdown at `Base 60m · Earned 0m · Used 0m · Locked 15m · Remaining 60m · Same-day overage 0m`.
Completing the newly selected main `qa-gaming-old` produced exactly one ledger row for 15 minutes and changed the visible breakdown to `Base 60m · Earned 15m · Used 0m · Locked 0m · Remaining 75m · Same-day overage 0m`.
A final relaunch preserved one ledger row totaling 15 minutes and preserved the visible earned breakdown.
Pixel evidence is stored in `evidence/01-initial-today.png`, `evidence/03-confirmation.png`, `evidence/04-moved.png`, `evidence/05-relaunch-persisted.png`, `evidence/06-old-no-reward.png`, `evidence/07-new-main-reward.png`, and `evidence/08-final-relaunch.png`.

## Cleanup

The signed app, helper, LaunchAgent, isolated QA root, installed application, install root, and temporary AX driver were removed.
No `ZoidCoachQA` or `ZoidCoachAgentQA` process remained and the QA LaunchAgent was absent.
Free disk after cleanup was 5.2 GiB.

## Current verdict

The repair makes the scenario reachable, deliberate, durable, and reward-correct, but it is not completely usable end to end because the confirmed move is visibly stale until refresh or relaunch.
The independent recommendation is `Touches remaining`, not `Fully implemented`.
The smallest repair is to derive `TodayPlanTaskRow.isMainObjective` from the matching live `DailyPlanEntry` when available and fall back to the snapshot row only when no plan entry exists.
