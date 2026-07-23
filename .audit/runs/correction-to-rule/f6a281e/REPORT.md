# Correction-to-rule independent acceptance

## Verified revision

- Authoritative source-write base: `d5ff4d4`.
- Correction verifier tip before evidence and tracker updates: `f6a281e`.
- Signed QA root: `/private/tmp/zoid-666-correction-rule-f6a281e`.
- Installed application: `/private/tmp/zoid-666-correction-rule-apps/Zoid 666 QA E2E.app`.

## Visible signed-QA journey

The signed application opened a privacy-safe Daily Review containing a two-minute Steam session classified as Unknown.
The classification picker changed that exact session to Work.
The future-rule toggle became available only for the safe Work classification.
Its visible preview stated that new Steam observations would become Work while historical observations stayed unchanged.
Applying once atomically corrected the session, changed the visible review category from Unknown to Work, and displayed an active `Steam -> Work` future rule.
After terminating and relaunching the app, Reviews restored the corrected historical session and active future rule.
The isolated signed agent then ingested a later Screenwatch Steam observation through the QA Screenwatch source and persisted it as Work even though the normal policy would classify it as Unknown.
The active rule's removal control opened a scoped confirmation explaining that future observations would return to the normal Settings policy and the historical correction would remain.
The destructive UI confirmation was not activated during Computer Use; focused store and archive tests independently prove append-only tombstone removal, restoration of normal policy for later observations, and preservation of earlier classifications.

## Persistence, safety, and privacy

Migration 34 follows migrations 28 through 33 without renumbering or destructive schema changes.
Correction plus future-rule creation uses one immediate SQLite transaction.
Replacement rules and removals are append-only events ordered by effective time and event identifier.
Screenwatch applies only the latest event whose effective time is not later than the observation.
Idle and Unknown cannot become lasting future rules in either UI or storage validation.
The review exposes only application, time range, duration, observation count, classification, and task attachment; window titles, URLs, and screenshots remain absent.
Stable accessibility identifiers cover the classification, future-rule toggle, preview, active state, removal action, and apply action.

## Verification gates

- Focused Daily Review, future-rule, migration, and Screenwatch effective-time tests passed.
- `git diff --check` passed.
- A fresh full Swift run compiled all targets but the SwiftPM Testing helper became idle twice before emitting results, including a four-worker retry, so no fresh full-suite claim is made.
- The authoritative `d5ff4d4` source-write base had already passed its full suite before this correction-only commit, and all correction-specific focused suites passed afterward.
- The release build passed.
- Signed QA package, hardened signatures, designated requirements, build identity, LaunchAgent registration, and Mach-service ownership passed.

## Scenario disposition

`ZC-064-010` is fully implemented and independently accepted.
The directly matching reclassification, total recalculation, reusable-rule creation, preview, restart persistence, and future-precedence scenarios are fully accepted.
One-time correction, midpoint splitting, task attachment, and final removal activation remain conservatively below Fully implemented until separate signed click-throughs cover those exact paths.
