# Maximum Intervention Level Claim

## Scope

- Scenario: `ZC-045-002`, Choose the maximum intervention level.
- Base: authoritative `290d55c`.
- Branch: `codex/maximum-intervention-level`.
- Worktree: `/private/tmp/zoid-666-maximum-intervention-level`.

## Owned files

- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `.audit/runs/maximum-intervention-level/candidate/CLAIM.md`
- `.audit/runs/maximum-intervention-level/candidate/REPORT.md`
- `docs/impl/666-BACKLOG.md`

## Acceptance

The end user can choose an explicit maximum intervention level in Settings, understand the exact lighter versus accountability-only behavior, save and restore the choice through the existing conflict-safe policy path, and receive no recovery prompt stronger than that persisted ceiling.
Tracker, registry, Lavish, packaging, and installed runtime are outside this candidate lane.
