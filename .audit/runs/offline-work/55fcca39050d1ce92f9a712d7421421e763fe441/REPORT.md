# Away-from-Mac Work Implementation Evidence

## Verified revision

- Commit: `55fcca39050d1ce92f9a712d7421421e763fe441`
- Branch: `codex/zc-calendar-planning`
- Build identity: `zoid-coach-55fcca39050d1ce92f9a712d7421421e763fe441-clean`
- QA root: `/private/tmp/zoid-666-offline-55fcca3`
- Signed application: `.build/app-qa/Zoid 666 QA.app`

## End-user result

The Reviews screen now lets a user add intentional away-from-Mac work for the selected day.
The user can record a start time, duration, optional task identifier or title, and an optional note.
Every entry remains visibly separate from Screenwatch-observed time while contributing to the combined actual-time total.
The screen explicitly states that missing telemetry is never inferred as work.
The user can edit the time, task, or note and can remove one entry through a scoped destructive confirmation.
Adding, editing, or removing an entry reopens a previously confirmed review so changed totals cannot silently influence learning.

## Persistence and recovery proof

- Migration 30 creates `offline_work_entries` with positive bounded duration and a day/start index.
- Create, update, read-after-restart, and delete use the canonical SQLite database.
- Updating the same entry identifier is idempotent and does not duplicate time.
- Review confirmation is cleared after every offline-work mutation.
- Removing offline work leaves Screenwatch behavior observations unchanged.
- Existing behavior evidence remains unchanged during migration.

## Automated verification

- Focused `swift test --filter DailyReviewTests`: passed.
- Focused `swift test --filter versionTwenty`: passed.
- Full `swift test`: 469 tests in 5 suites passed in 26.513 seconds.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests`: 41 tests passed.
- `swift build -c release`: passed.
- Clean signed-QA packaging: passed.
- Deep strict code-sign verification: passed.
- Package identity, LaunchAgent, Mach service, and signing identity coherence: passed.

## Four-worker test note

One four-worker run completed and exposed six migration expectation failures caused by the new version 30.
Those expectations were corrected and their focused regression suite passed.
Two subsequent explicit four-worker runs reached an idle `swiftpm-testing-helper` process with no child test process and produced no completion output.
The process was terminated after the hang repeated.
The ordinary full test command then ran the complete 469-test Swift Testing suite successfully.

## Scenario scope

- `ZC-022-003` now has a complete in-app daily-review entry flow pending independent signed-QA click-through.
- `ZC-022-004` now shows actual time as observed plus away-from-Mac work pending independent signed-QA click-through.
- `ZC-022-005` now preserves and displays away-from-Mac and Screenwatch-observed time separately pending independent signed-QA click-through.
- `ZC-022-006` now supports correction with immediate recalculation and restart-safe persistence pending independent signed-QA click-through.
- `ZC-022-007` now explicitly distinguishes intentional offline work from missing telemetry pending independent signed-QA click-through.
- `ZC-022-001` and `ZC-022-002` remain incomplete because the active-task surface does not yet expose this flow directly.

## Independent verification handoff

Open the exact signed-QA build, finish or restore onboarding, and navigate to Reviews.
Add a 30-minute away-from-Mac entry with a task and note.
Verify the Actual Time value increases by 30 minutes while Screenwatch-observed time remains unchanged.
Edit the entry to 45 minutes and verify the total changes without creating a duplicate.
Relaunch and verify the corrected entry and separated totals persist.
Remove the entry through the confirmation and verify observed sessions remain.

## Rollback

Revert commit `55fcca39050d1ce92f9a712d7421421e763fe441` before migration 30 is integrated.
After migration 30 is integrated, leave the additive table in place and revert only the application and store consumers.
