# Accepted Break Lifecycle Candidate

## Claim

- Scenario IDs: `ZC-028-001`, `ZC-028-002`, `ZC-028-004`, `ZC-028-005`, `ZC-028-006`, `ZC-028-007`, `ZC-028-008`, and `ZC-028-009`.
- Production files: `Sources/ZoidCoachCore/TodayDashboard.swift`, `Sources/ZoidCoachApp/MenuBarCoachView.swift`, `Sources/ZoidCoachApp/Views/DashboardView.swift`, and the minimum task execution or notification files required by the implementation.
- Test files: focused accepted-break lifecycle tests only.
- Excluded: onboarding, work-window scheduling, weekday controls, tracker, registry, Lavish, root runtime, and `ZC-028-003`, which is already independently verified.

## Acceptance Target

An active task can enter a clearly timed accepted break from Today or the menu bar, show neutral break state and remaining time, receive a local end reminder, end early or at expiry, and resume the same task without producing drift coaching during the break.

## Implemented

- An open durable `.break` pause now produces a restart-safe `AcceptedBreakSnapshot` from its persisted pause timestamp rather than UI-only state.
- Today shows a live 15-minute countdown, explicitly describes the interval as a break rather than drift or failure, changes to an ended state at expiry, and offers End Break Early or Resume Task.
- The menu bar offers `BREAK 15`, shows the same live or ended state, and changes Resume to End Break while the break is open.
- Today and menu-bar mutations reconcile one replacement-safe local break-end notification and cancel it when the task resumes.
- The existing gaming-drift producer continues to suppress coaching while the same durable break pause is open.
- No task is resumed automatically at expiry, so the user retains control and the break remains visibly ended until they choose Resume.

## Focused Proof

- `swift test --filter AcceptedBreakLifecycleTests` passed.
- `swift test --filter "(AcceptedBreakLifecycleTests|TaskExecutionStoreTests|TodayDashboardAgentTests|MenuBarCoachTests|GamingDriftPromptServiceTests)"` passed.
- The focused journey proves start, persisted timestamp, countdown, expiry copy, restart restoration, early resume, and removal of accepted-break state.
- `git diff --check` passed.

## Verifier Plan

1. Rebase the candidate onto the current authoritative branch and rerun the focused suites.
2. Package and install signed QA with an isolated database and healthy notification authorization.
3. Start a real task in Today, choose Take a break, verify the visible 15-minute countdown and neutral copy, relaunch, then end the break early and confirm the same task resumes.
4. Repeat from `BREAK 15` in the menu bar and confirm the menu status changes to End Break.
5. Use a clock-controlled or shortened verifier fixture to prove the one local reminder, ended state, and user-controlled resume without waiting 15 wall-clock minutes.
6. Seed qualifying gaming observations during the open break and confirm no coaching prompt is created.
7. Only after those installed checks, update the tracker, registry, backlog, and Lavish artifact conservatively.
