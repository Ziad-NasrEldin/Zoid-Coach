# Canonical Onboarding Test-Prompt Implementation Proof

## Scope

This batch implements the canonical onboarding prompt loop for `ZC-004-003` and `ZC-004-005`.

It also strengthens the notification delivery and fallback path used by `ZC-004-001`, `ZC-004-002`, and `ZC-004-004`.

## End-User Outcome

- The delivery-proof step creates one harmless prompt in the agent-owned prompt inbox.
- The prompt is idempotent for one onboarding flow and cannot multiply when the user retries.
- Authorized notifications receive the same prompt and the same two bounded actions as Today.
- Denied or unavailable notifications fall back to the onboarding surface and Today without blocking setup.
- The user must resolve the prompt before Continue becomes available.
- The local test-task completion and prompt response both survive restart.
- A user who exits setup sees a persistent Resume Setup strip above Today.
- Foreground activation and a visible refresh control reconcile notification actions completed outside the onboarding window.

## Durable Boundaries

- The app requests prompt creation through the signed same-user XPC boundary.
- Only the agent writes the canonical `PromptInboxStore`.
- The prompt uses the dedicated `ONBOARDING_TEST` category.
- Only `continue_intentionally` and `ignore` are accepted for this category.
- Prompt response tokens, response idempotency, and the existing prompt-effect ledger remain authoritative.
- Existing onboarding progress decodes with `deliveryTestTaskCompleted` defaulting to false.

## Automated Proof

- `swift test --jobs 4 --filter onboardingTestPrompt` passed.
- `swift test --jobs 4 --filter onboardingPromptNotificationAcceptsOnlyItsHarmlessActions` passed.
- `swift test --jobs 4 --filter canonicalDeliveryPromptAndLocalTaskSurviveRestartAndGateContinuation` passed.
- `swift test --jobs 4 --filter freshOnboardingPersistsEachStepAndResumesAfterRestart` passed.
- `swift build -c release --jobs 4 --scratch-path .build-release-canonical` passed.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests` passed all 41 tests.

## Remaining Parallel Acceptance

The root tracker and registry remain unchanged in this branch.

A fresh verifier must install the signed QA product, complete the prompt through both the notification and Today surfaces, relaunch, use Resume Setup, and confirm the resolved state before the scenarios qualify as fully implemented.
