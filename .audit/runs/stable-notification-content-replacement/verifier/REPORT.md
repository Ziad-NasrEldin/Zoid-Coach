# ZC-054-009 Independent Verification Report

## Recommendation

Keep ZC-054-009 at **Touches remaining**.
The candidate closes the stable and privacy-safe request-identity implementation gap, but the installed application still lacks a safe visible control that creates two different unresolved prompt episodes for one logical decision with changed content.
Actual Notification Center replacement and response routing through the newest episode therefore remain unproved end to end.

## Integration identity

The verified implementation object is `9167a91e21ba80be3ee06c2a992b8289d16736cb`.
The complete isolated verification tip is `3aa7098c8430b1c094ccce636528b438b3f675d3`.
These exact objects supersede an earlier handoff message that expanded the correct short verification SHA to an incorrect full hash before integration began.

## Verified implementation

Prompt notification request identifiers now use the runtime-specific prompt namespace followed by `decision.` and the first 128 bits of the logical decision key's SHA-256 digest.
The raw decision key, prompt title, prompt body, and transient episode identifier do not appear in the request identifier.
Two prompt episodes for the same logical decision produce the same request identifier.
Different logical decisions produce different request identifiers.
Production and signed-QA namespaces remain separate.
An empty legacy decision key receives a deterministic private fallback derived from the episode identifier.

The fixed golden vector for `plan:private-client-title` is `b91ecd4e3cf7ff1d0958dc904682de59`.
That fixed expectation makes cross-process determinism explicit rather than merely comparing two calls in one process.

## Durable fixture journey

A focused verifier test schedules an earlier episode, reconstructs both the fixture adapter and notification coordinator, and schedules a new episode with the same logical decision key.
The persisted fixture retains exactly one notification.
The retained notification carries the newest episode identifier, newest title, and newest body, and is delivered rather than left stale.
Disabling prompt notifications removes the replacement notification.
A second adapter reconstruction confirms the cancelled notification does not return after relaunch.

## Automated evidence

`swift test --filter PromptNotificationCoordinatorTests` passed after adding the golden-vector and relaunch journey.
`swift test --filter QAFixtureOSCompositionTests` passed.
`swift test --filter PromptNotificationRelevanceTests` passed.
The first notification-wide run passed 39 of 40 tests and exposed only the authoritative base's stale migration expectation that version 42 should equal 38.
After the migration-consistency repair became authoritative at `b936fcc783da0814cb83157c0a662e5812723cf9`, the candidate was rebased and `swift test --filter Notification` passed all 40 tests.
`swift build -c release` passed.
`git diff --check` passed.

## Signed runtime evidence

The candidate packaged and installed successfully as an isolated signed QA application at `/private/tmp/zoid-666-notification-replacement-install/Zoid 666 QA E2E.app`.
Code-signature verification, QA LaunchAgent registration, installed helper path validation, and isolated ready-state preparation passed.
The first native Accessibility and pixel probe attached to the intentional `--background-schedule` process and correctly found no on-screen application window.
A foreground application process was launched, but the serialized runtime cap expired before the candidate-specific notification replacement journey could be created and inspected.
The runtime was uninstalled and the lease was released without changing production data, real notification permission, or production Notification Center state.

## Remaining acceptance gap

The installed product needs a safe QA-only, user-visible control that can create an initial prompt and then create a second episode for the same logical decision with updated title, body, and actions.
An independent verifier must then prove Notification Center shows exactly one newest card, the newest action routes through the newest prompt identifier, a distinct logical decision remains distinct, and the obsolete card does not return after app and helper relaunch.
Until that installed-app proof exists, implementation and deterministic integration evidence are not sufficient for a Fully implemented status.

## Changed files

- `Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift`
- `Tests/ZoidCoachAppTests/PromptNotificationCoordinatorTests.swift`
- `.audit/runs/stable-notification-content-replacement/verifier/REPORT.md`
