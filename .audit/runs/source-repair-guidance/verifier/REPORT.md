# Source repair guidance verifier report

## Result

The source-health ledger now explains the exact safe impact of every unhealthy source and labels every existing source-specific control with a stable accessibility identifier and truthful action hint.
Healthy rows stay concise.
Checking rows disable their control.

## Verifier correction

The candidate UI disabled a repair control only after the model published a checking state.
The underlying `AppModel.checkSource` method did not guard the interval before an asynchronous adapter returned, so rapid activation could start duplicate permission or repair requests.
The verifier added a synchronous per-source in-flight set, publishes Checking immediately, and ignores a second activation until the first request completes.
A focused gated-service regression proves exactly one adapter request and the final Healthy transition.

The verifier also corrected notification and Screenwatch accessibility hints that overstated the current control.
Those controls recheck the source; their hints now direct the user to Settings for the actual macOS or folder repair path when needed.

## Verification

- `swift test --filter SourceRepairGuidanceTests` passed.
- `swift test --filter SourceHealthTests` passed.
- `swift test --filter repeatedSourceRepairActivationStartsOnlyOneInFlightRequest` passed.
- `swift build -c release` passed.
- Signed QA packaging and package, signature, LaunchAgent, and Mach-service verification passed.
- The signed QA runtime installed and the exact app process launched from the isolated install root.

## Conservative acceptance boundary

The computer-use accessibility server timed out while reading the running signed app.
The ten-minute UI cap ended before representative healthy, checking, denied, unavailable, and attention screenshots or repair clicks were captured.
`ZC-048-008` and `ZC-048-009` therefore remain `Touches remaining`.
