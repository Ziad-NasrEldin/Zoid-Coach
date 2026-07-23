# Reduced-motion state feedback claim

## Baseline

- Authoritative root: `73ee377`.
- Branch: `codex/reduced-motion-feedback`.
- Worktree: `/private/tmp/zoid-666-reduced-motion`.

## Scenario ownership

- `ZC-055-011`: Use reduced motion without losing state-change feedback.
- `ZC-056-010`: Avoid distracting motion or celebratory feedback around interruptions.

## File ownership

- `Sources/ZoidCoachApp/Design/SumiTheme.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`
- `Tests/ZoidCoachAppTests/SumiThemeTests.swift`
- `.audit/runs/reduced-motion-feedback/candidate/`
- `docs/impl/666-BACKLOG.md`

## Acceptance boundary

- Every state transition owned by these surfaces removes movement and scaling when macOS Reduce Motion is enabled.
- Reduced motion preserves immediate opacity or identity feedback so state changes remain understandable.
- Normal mode retains the existing restrained short transitions.
- The focused contract is deterministic and does not require changing the user's system setting.

## Exclusions

This lane does not touch Daily Review files, root, installed runtime, tracker, registry, Lavish, notification delivery, prompt persistence, or task mutation.
