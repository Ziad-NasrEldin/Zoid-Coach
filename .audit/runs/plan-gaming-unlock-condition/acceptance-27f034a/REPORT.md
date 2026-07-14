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

## Pending acceptance gates

The focused red-capable command is `swift test --filter GamingUnlockConditionPresentation`.
It exercises the exact locked label, non-main action, confirmation gating, accessibility consequence, and ordinary fallback state.
The focused command passed with process exit 0 on 14 July 2026.
The selected Swift Testing run executed both `Plan gaming unlock condition` and `Reachable Today gaming unlock control` without a failure.
The single `swift build -c release` invocation passed with process exit 0 and produced executable `.build/release/ZoidCoach`.
The build lease ended with 5.0 GiB free on the Data volume.
The signed two-task Cancel, confirm, relaunch, old-task no-reward, new-main reward, and exactly-once journey is pending the root-owned serialized runtime lease.

## Current verdict

The source review found no conflict or source-level defect in the transplanted repair.
`ZC-008-016` remains `Touches remaining` until the complete signed-runtime gate finishes.
