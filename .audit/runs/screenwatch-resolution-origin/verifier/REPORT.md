# ZC-049-003 Resolution-Origin Verification

## Verdict

The source candidate is accepted, but the signed end-to-end journey is inconclusive.
`ZC-049-003` must remain **Touches remaining**.
No tracker, registry, or Lavish status was changed.

## Candidate identity

- Canonical rebase base: `cb27c619b415c6a6adef103b0690cf6068b98f73`.
- Rebased source commit: `38b2749`.
- Rebased candidate evidence commit: `1eeaea7`.
- Evidence newline normalization commits: `88b9a81` and `c999e9a`.
- Exact signed verifier package commit: `d1bff474f7fe3451ee274b958bc734950ceab1a0`.
- Signed app executable SHA-256: `359126884b8897d6812c1fd470c1924cf1aec272a647526f06b6a1b3c8ca554a`.
- Signed helper executable SHA-256: `8d4f7f63330a23973bba2406a93902d46c0f5bdb67bee8646f7de402f55d61d4`.

The QA package verified as `zoid-coach-d1bff474f7fe3451ee274b958bc734950ceab1a0-clean`.
Deep code-signing verification, package identity verification, XPC registration, migration version 45, and SQLite `quick_check` passed.

## Independent source audit

The production and focused-test diff changes exactly four source files and four test files.
Migration 45 adds nullable constrained `resolution_origin` and `resolution_reason` columns without rewriting legacy rows.
Legacy null metadata remains conservative and continues to count as handled.
Only the exact `system` plus `screenwatch_evidence_invalid` pair bypasses same-session deduplication, cooldown, and daily-cap queries.
Explicit user dismissal records `user` plus `explicit_dismissal` and continues to count as handled.
Calling system withdrawal after a completed user dismissal preserves the original user resolution.
The notification coordinator still removes only resolved prompt notifications with its own request prefix and preserves unrelated notifications.

The recorded focused run proves 5 of 5 recovery-contract tests passed.
The recorded relevant suite proves 79 of 79 tests passed.
The recorded release build passed.
The logs were independently inspected and only their CRLF newlines were normalized.

## Signed runtime result

The first isolated run exposed a fixture and WAL ownership race.
A signed `ZoidCoachQA --background-schedule` process survived a name-based process stop while the fixture database was being reseeded.
That live database later claimed schema version 45 while the migration-33 and migration-34 tables were absent.
The verifier did not manufacture or repair those tables.

One fresh isolated database was then materialized as the only permitted rerun.
The helper and app were stopped by exact installed path before seeding, the WAL was checkpointed, and the untouched database proved schema version 45, both required tables, and `quick_check: ok`.
The signed helper then ingested 70 Screenwatch observations classified as gaming.
The signed Today snapshot showed current Screenwatch coverage, 70 meaningful gaming minutes, a 60-minute budget, zero unlocked minutes, 10 minutes of overage, seven complete baseline days, and one incomplete main objective.
No gaming-drift prompt appeared inside the bounded acceptance window.

Because the initial prompt did not appear, the signed run could not prove stale or future invalidation, pending or delivered notification withdrawal, same-session fresh recovery, visible user dismissal, cooldown and daily-cap preservation, or app and helper restart semantics.
Deterministic tests cover those behaviors, but they do not replace the requested signed end-to-end proof.

## Cleanup

The QA LaunchAgent was unregistered and booted out.
The signed QA app, both isolated QA roots, and temporary manifests were removed.
Notification permission was not changed.
No destructive system action was performed.
