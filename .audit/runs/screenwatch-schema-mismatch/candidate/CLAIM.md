# Screenwatch Schema Mismatch Candidate Claim

Scenario ownership: `ZC-049-008`.

This lane distinguishes a changed or unsupported Screenwatch record schema from an empty stream or generic read failure, without displaying captured content.

Owned product files:

- `Sources/ZoidCoachApp/Services/ScreenwatchReader.swift`

Owned focused test files:

- `Tests/ZoidCoachAppTests/ScreenwatchReaderTests.swift`

Owned evidence and backlog files:

- `.audit/runs/screenwatch-schema-mismatch/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane does not own root or runtime state, the scenario tracker, the scenario registry, Lavish artifacts, AppModel, Screenwatch policy, Settings, or agent files, prompt task-block files, active commitment or menu files, notification files, source bookmarks, or source-owned Screenwatch data.
