# Screenwatch Schema Mismatch Verification

## Decision

`ZC-049-008` advances from Not implemented to Touches remaining.

The scenario does not qualify as Fully implemented because the complete installed healthy, changed-schema, mixed-schema, repaired, and relaunch sequence was not captured.

## Lineage and focused proof

The candidate was rebased onto authoritative ingestion-control root `4c2a75d` as `09cb7e3`.

The only rebase conflict was the shared Screenwatch backlog row, which now preserves both ingestion-control and schema-mismatch evidence without changing product behavior.

One `swift test --filter ScreenwatchReaderTests` invocation passed all four selected tests with exit code 0.

The focused proof covers a healthy schema-valid stream, a missing stream, a complete changed-schema record containing private sentinel content, and a mixed valid plus changed-schema stream.

The user-visible evidence is limited to aggregate parsed, image-reference, and unsupported-schema counts.

The private title is explicitly absent from the generated health evidence, and the implementation never adds captured application, title, URL, or malformed record content to the health message.

## Signed package and installed boundary

One release package installed `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app` against isolated root `/private/tmp/zoid-666-screenwatch-schema-qa`.

Packaging, code signing, designated requirement, embedded helper identity, LaunchAgent registration, and exact helper startup passed.

The signed app visibly exited onboarding and opened Source Health.

Source Health exposed the real Screenwatch row, privacy-safe impact guidance, and the stable `source-health-screenwatch-repair` action while the initial state was unavailable.

A fresh schema-valid QA record containing private app, title, and URL sentinels was placed only under the isolated Screenwatch source root.

The first visible recheck was initiated, but Computer Use repeatedly failed with ScreenCaptureKit error `-3811` before the result could be inspected.

After the failure repeated more than twice, the verifier stopped the visual path within the cap and did not claim healthy, mismatch, mixed, repair, or relaunch states as visibly proven.

## Cleanup and remaining acceptance

The signed app and helper were stopped, the QA LaunchAgent was unregistered, and the installed app plus isolated runtime root were removed.

`launchctl` confirmed that `qa.ziadnasreldin.ZoidCoach.agent` was absent after cleanup.

One fresh signed run still needs to visibly prove healthy, changed-schema, mixed-schema, repaired-healthy, and relaunch states through the same Source Health surface.

That run must confirm aggregate counts, direct Repair guidance, absence of captured private content, and recovery without duplicate or stale mismatch counts.
