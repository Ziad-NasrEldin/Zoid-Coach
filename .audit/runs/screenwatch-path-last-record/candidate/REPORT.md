# ZC-048-002 Candidate Report

## Outcome

The Source Health Screenwatch card now receives and visibly presents the canonical days-folder path together with the absolute date and time of the latest schema-valid local record.
The path is selectable, the date and time follow the current locale and time zone, and VoiceOver receives one factual summary without captured titles, URLs, screenshots, or credentials.

## Behavior

- Healthy and stale inspections preserve the canonical resolved folder path and latest valid record instant.
- Schema mismatch inspections preserve the safe resolved folder path but do not invent a valid-record time.
- Missing-record presentation explicitly says that no valid record is available yet.
- The UI exposes stable `settings.screenwatch.source-path`, `settings.screenwatch.last-valid-record`, and `settings.screenwatch.record-evidence` accessibility identifiers.
- Existing source status, repair guidance, and privacy-safe diagnostics remain available.

## Verification

- `swift test --filter "screenwatch(Setup|Connection|RecordEvidence)"` passed 16 focused tests.
- `swift build -c release` passed.
- `git diff --check` passed before handoff.

## Remaining Acceptance

An independent verifier must install the signed QA build with a controlled current or stale Screenwatch fixture, open Source Health, confirm the exact path and absolute latest-record time visually and through accessibility, relaunch, and confirm the same evidence remains accurate.
Only the root integrator may update the authoritative tracker and registry after that verification.
