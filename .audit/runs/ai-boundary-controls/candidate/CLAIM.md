# Optional AI boundary controls claim

## Baseline

- Authoritative baseline: `6b55ad4`
- Branch: `codex/rules-only-boundary`

## Scenario ownership

- `ZC-046-004` - Choose local or remote processing when supported.
- `ZC-046-005` - Preview a representative redacted payload before enabling remote AI.
- `ZC-046-007` - Clear the AI cache.

## File ownership

- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Sources/ZoidCoachApp/Views/RemoteEvidencePreview.swift`
- `Tests/ZoidCoachAppTests/RemoteEvidencePreviewTests.swift`
- Candidate evidence under `.audit/runs/ai-boundary-controls/candidate/`.

## Boundaries

This lane does not touch Reminders services, Reminders outage continuity, runtime installation, tracker, registry, Lavish, or root.
It reuses the existing authenticated AI-metadata deletion command instead of adding a second destructive path.
