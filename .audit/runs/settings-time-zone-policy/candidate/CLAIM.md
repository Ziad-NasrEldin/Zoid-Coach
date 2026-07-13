# Settings time-zone policy claim

This isolated lane starts from authoritative commit `4cc05de`.

Higher ready backlog items are signed-runtime proof or already-delivered onboarding and notification candidates.
This lane claims the first unimplemented, disjoint Settings policy gap that affects every local-day calculation.

## Scenarios

- `ZC-044-005` - Configure time-zone behavior.
- `ZC-053-009` - Change time zones and retain accurate historical event times.

## Owned files

- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`.
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`.
- `Sources/ZoidCoachApp/Views/SettingsView.swift`.
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`.
- `.audit/runs/settings-time-zone-policy/candidate/*`.

## Boundaries

This lane exposes the persisted policy time zone, validates it, merges concurrent edits safely, and explains that historical event instants remain unchanged while future local-day boundaries use the selected zone.
It does not implement the separate cross-local-day plan-move confirmation scenario.
It does not touch review reminders, ActionCommand, AgentMain, root, installed runtime, tracker, registry, backlog, or Lavish.
