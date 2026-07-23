# ZC-053-010 Time-Zone Local Plan-Day Confirmation Candidate

## Scope

This candidate adds the missing confirmation boundary before a policy time-zone change switches the current local plan day.
It does not change the authoritative scenario tracker or registry.

## End-user behavior

Settings compares the saved and proposed policy time zones at Save time.
A read-only inspection counts the planned tasks on the saved policy's current local day.
When the proposed time zone maps the same instant to another date and the source day contains a plan, Save pauses and shows a native confirmation.
The confirmation names the task count, source day and time zone, destination day and time zone, and explains that saving changes which local plan day Zoid 666 treats as current.
Cancel performs no mutation and preserves the draft for review.
Confirm resumes the normal version-checked agent policy save, so stale-version detection, audit receipts, and conflict recovery remain intact.
Changes that stay on the same local day or have no source-day plan save without an unnecessary prompt.
If the plan cannot be inspected, Settings refuses to save and reports the safety-check failure.

## Changed files

- `Sources/ZoidCoachInfrastructure/TimeZonePlanMoveInspector.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyController.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/TimeZonePlanMoveInspectorTests.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `docs/impl/666-BACKLOG.md`

## Verification

- The focused time-zone inspector and confirmation-gate test selection passed.
- `swift test --filter SettingsPolicy` passed.
- `swift build -c release` passed with exit code 0.
- The real SQLite test creates a two-task UTC plan at `2026-07-14T00:30:00Z` and proves Los Angeles maps the same instant to `2026-07-13` with the exact two-task warning.
- Controller tests prove Cancel makes no mutation, Confirm creates the next durable policy version, no-plan changes save directly, and inspection failure blocks the save.

## Independent acceptance remaining

An independent verifier must seed a signed QA plan near a controlled cross-zone day boundary, open Settings, change the time zone, prove Save pauses with the exact native warning, prove Cancel preserves the old durable policy and unsaved draft, then Confirm and verify the saved policy and truthful plan-day state after app and helper relaunch.
