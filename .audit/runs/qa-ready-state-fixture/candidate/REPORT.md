# QA ready-state fixture candidate

## Result

The candidate provides a deterministic isolated-QA path that bypasses completed onboarding and opens a signed package at Today.
Production runtime behavior is unchanged.
No application, helper, LaunchAgent, real permission, or real operating-system source was installed or mutated during this batch.

## Processing-artifact repair

The signed verifier exposed a generated seed whose notification ID was `qa-ready-notification` while its nested prompt ID was `qa-ready-prompt`.
The helper correctly rejected that seed through the canonical persisted-state invariant, leaving the control request in processing and canonical fixture state empty.
The example manifest now uses one canonical notification identity, and the strict preparer rejects any future notification whose nested prompt ID differs from its fixture ID before replacing the target root.
No production fixture-consumption code changed.

## Delivered infrastructure

- `Scripts/prepare-qa-ready-state.py` strictly validates a versioned manifest before writing anything.
- `Scripts/fixtures/qa-ready-state.example.json` demonstrates granted Reminders, Calendar, Screenwatch, and notification fixtures.
- Generated onboarding progress is valid, contiguous, 12 of 12 complete, and explicit about granted or deferred access decisions.
- Generated operating-system state enters through the existing `QAFixtureOSControlRequest.seed` schema.
- Optional Screenwatch records remain under `Screenwatch/days` inside the isolated QA root.
- `Scripts/qa-window-content-probe.swift --expect-today` verifies Today through native Accessibility and optional pixel capture without changing the existing onboarding mode.
- `docs/QA-READY-STATE-VERIFICATION.md` records the package, launch, and verification sequence.

## Proof

`swift test --filter qaReadyState` passed the focused ready-state tests.
The granted-state test loaded generated progress through `OnboardingProgressStore`, processed the generated control through `QAFixtureOSComposition`, and confirmed one Reminder, one Calendar commitment, one notification, and healthy Screenwatch data.
The deferred-state test confirmed finished onboarding with deferred Reminders, Screenwatch, and notifications plus not-determined fixture permissions.
The malformed-state test confirmed exit status 2 and preserved the only file in an existing target root.
The notification-identity regression confirmed a mismatched nested prompt ID exits with status 2 before replacement and preserves the only file in the target root.
The exact helper-consumption regression renamed the generated request to `os-fixture-request.processing.json`, fed it through an independent helper consumer, and confirmed finished onboarding, committed canonical state, snapshot output, and processing-file removal.
That exact regression failed twice before the fixture correction and passed twice afterward.
`python3 -m py_compile Scripts/prepare-qa-ready-state.py` passed.
`swiftc -typecheck Scripts/qa-window-content-probe.swift` passed.
`swift build -c release` passed.
`git diff --check` passed.

## Fresh verification boundary

A fresh verifier must package against a prepared root, launch the signed QA app directly, and prove Today plus pixel evidence with `--expect-today`.
Installed-helper reuse must be verified separately under the serialized runtime lease.
