# Zoid 666 privacy-data acceptance report

Commit `73c77ec` completes backlog slice 20 on branch `codex/zc-privacy-data-slice`.

## User outcomes delivered

- Settings lists every stored-data class with a local record count, database path, database size, and schema version.
- Settings explains that credentials live separately in Keychain and that source screenshots remain owned by their source application.
- A user sees the exact redacted diagnostic manifest before export.
- A user chooses the JSON export destination with the native macOS save panel.
- The export excludes titles, conversation text, URLs, file paths, event names, payloads, screenshots, and credentials.
- A user can inspect recent derived behavior sessions and delete one exact session.
- A user can delete today, an inclusive date range, extracted conversation text, all raw behavior metadata, AI request metadata, reviews and learned rules, or all local database records.
- Every destructive operation has a specific confirmation that explains its scope and what remains untouched.
- The Today snapshot and local inventory refresh after a successful deletion so removed evidence does not remain represented as current.
- Retention is independently configurable for screenshots, extracted text, behavior records, task sessions, prompts, reviews and learning, and diagnostics.
- Background maintenance enforces each retention policy locally while preserving unresolved prompts and source-owned screenshots.
- Delete-all preserves the migrated empty schema so Zoid 666 can restart safely.

## Scenario impact

- `ZC-047-001` through `ZC-047-015` now have implementation evidence for the privacy-data surface.
- `ZC-048-009` gains a reviewed diagnostic export flow.
- `ZC-064-011` gains dependency-free local export and deletion implementation.

The root tracker integrator owns final status upgrades after independent visible-app verification.

## Automated proof

- `swift test --filter "Privacy(DataService|DeletionRange)"` passes.
- `swift test --filter screenwatchMaintenanceAppliesIndependentBehaviorSessionPromptAndReviewRetention` passes.
- `swift test` passes 444 tests in four suites.
- `swift build -c release` passes.

## Safety properties

- Date-range deletion uses local calendar boundaries and includes the full user-visible THROUGH date across daylight-saving transitions.
- Session deletion matches its exact application and inclusive epoch range.
- Behavior deletion never removes Screenwatch source files.
- Export rejects non-JSON destinations and symbolic-link targets.
- Delete-all excludes schema migration records and system tables.
- UI mutations continue to route through the background agent.
