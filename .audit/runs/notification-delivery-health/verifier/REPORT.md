# Notification Delivery Health Verification

## Authoritative integration

The notification candidate was rebased onto authoritative daily-plan tip `7988963`.
Migration 35 retains the authoritative `addColumnIfTableExists` recovery behavior.
Migration 36 follows migration 35 and exclusively adds `notification_delivery_events` plus its two indexes.
Candidate commit `05c5604` was merged into `codex/full-system` at `498bca9bfde5` after daily verifier fix `15a43b1`.
The ancestry check proved `15a43b1` is a direct first-parent ancestor of `498bca9bfde5`.

## Verification

- `swift test --filter 'NotificationDelivery|OnboardingTestPromptService|AutonomousDatabaseMigrator|PrivacyDataService'` passed after the authoritative rebase.
- The focused sequence covers notification outcomes, replacement attempts, fallback, restart durability, retention, privacy deletion, migration ordering, and legacy migration recovery.
- `git diff --check` passed before integration.
- The integrated root full Swift suite passed with 565 tests in 7 suites at `498bca9bfde5`.
- Release and signed-QA verification were stopped before mutation when the root orchestrator assigned the serialized runtime and tracker lease to the daily-plan verifier.

## Honest acceptance state

The code, migration, focused integration, and full automated suite are proven.
The affected scenarios remain short of fully implemented until the serialized signed-QA Settings inspection exercises authorization unavailable, repair, refresh, accepted-by-macOS wording, stable replacement history, restart recovery, and privacy-safe visible content.
The tracker, registry, and Lavish report remain unchanged under the root-owned serialized lease.

## Serialized runtime preparation

`Scripts/notification-delivery-acceptance.py` now prepares three isolated signed-QA roots for delivery and replacement, injected scheduling failure, and denied-to-repaired authorization.
The deterministic fixture supports a bounded QA-only notification scheduling failure that records a truthful sanitized `scheduling_failed` ledger outcome without touching the production notification center.
The harness refuses to overwrite non-empty evidence roots, queues repair only after the denied fixture was processed, and exports a privacy-safe evidence summary without prompt identifiers, request identifiers, titles, bodies, actions, or error text.
`.audit/runs/notification-delivery-health/acceptance-mapping.json` maps every targeted tracker ID to its exact visible and machine proof plus the maximum status the harness can honestly justify.
Four Python harness tests passed.
Eleven focused Swift notification and migration tests passed, including injected failure and changed-content replacement without stacking.
The broader `QAFixture` focused group passed after the fixture schema addition, proving backward-compatible decoding and control behavior.
The shared release, package, runtime, tracker, registry, and Lavish surfaces remain untouched until the daily verifier releases its lease.
