# Screenwatch Ingestion Control Verification

## Decision

`ZC-039-009` advances from Not implemented to Partially implemented.

The user-facing preference and central ingestion gate are present and focused-green, but the capped signed runtime did not establish the healthy imported baseline required to prove pause and resume end to end.

## Verified lineage

Candidate `848bf9d` was independently rebased once onto authoritative `b0ad652` as `6294c64a01af31df3bc79b85a7cd6b5d5522d2aa`.

The signed release identified itself as `zoid-coach-6294c64a01af31df3bc79b85a7cd6b5d5522d2aa-clean`, version 0.1.0 Build 8.

## Focused proof

One combined focused invocation passed the new `ScreenwatchIngestionControlTests`, legacy CapturePolicy decode and paused round-trip, Settings round-trip and unrelated-conflict merge, and broader `UserPolicyTests` selection.

The inspected implementation defaults legacy policy documents to ingestion enabled, persists the explicit choice, merges it independently from unrelated Settings edits, blocks both maintenance and live source reads while paused, and re-reads the current policy on every watch-loop pass.

No verifier code fix was required.

## Release and signed runtime proof

The single release package passed the production build, coherent bundle, helper, and Mach identities, deep signing, nested helper validation, and designated-requirement validation.

The exact helper ran from `/private/tmp/zoid-666-screenwatch-ingestion-install/Zoid 666 QA E2E.app/Contents/MacOS/ZoidCoachAgentQA` with isolated state under `/private/tmp/zoid-666-screenwatch-ingestion-qa`.

Signed Settings visibly exposed `INGEST NEW SCREENWATCH ACTIVITY` as ON with accessibility identifier `settings.screenwatch.ingestion-enabled`.

The adjacent copy stated that new records can update behavior evidence while existing Zoid 666 history and source-owned files remain unchanged.

The isolated source status was `EXPECTED FOLDER, WAITING FOR TODAY'S LOG` before the verifier created one valid local observation under the QA-only `Screenwatch/days/2026-07-13/log.jsonl` path.

At the bounded source-fixture deadline, the source file still contained exactly one record, while `behavior_records` remained zero and no `screenwatch-canonical-source` checkpoint existed.

The verifier therefore stopped without claiming pause, relaunch, resume, or exactly-once runtime behavior.

## Remaining acceptance

Start from an isolated QA source that has already imported one baseline observation and reports healthy.

Pause and save through signed Settings, append one observation, wait through two watch loops, relaunch, and prove the new record remains unimported while baseline history and both source records remain intact.

Resume through Settings without restarting the helper and prove the waiting observation imports exactly once.

Finally, save one unrelated Settings change from a concurrent draft and prove it does not overwrite the resumed ingestion choice.

## Cleanup

The signed app and exact helper were unregistered and stopped, the QA application and isolated data roots were removed, and `launchctl` confirmed the service was absent before the runtime lease was released.
