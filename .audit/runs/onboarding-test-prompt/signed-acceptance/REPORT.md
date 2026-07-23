# Canonical Onboarding Prompt Signed-QA Acceptance

## Scope

This run independently verifies the canonical onboarding prompt loop in the installed, signed Zoid 666 QA product at implementation tip `8297095`.

The acceptance covers notification delivery and action resolution, denied-notification Today fallback, durable prompt identity and response state, paused-setup recovery, exact-step Resume Setup, and relaunch durability.

## Installed product

- Package: `/private/tmp/zoid-666-canonical-accept/.build/app-qa/Zoid 666 QA.app`.
- Installed application: `/private/tmp/zoid-666-canonical-install/Zoid 666 QA E2E.app`.
- Isolated QA root: `/private/tmp/zoid-666-canonical-prompt-qa`.
- LaunchAgent: `qa.ziadnasreldin.ZoidCoach.agent`.
- The packaging verifier passed the app, agent, LaunchAgent, Mach service, signing identities, and clean build identity.
- The install verifier confirmed that the registered and running QA helper belonged to the installed application.

## Notification path

- The QA notification permission was seeded as granted without touching the production notification center.
- Step 5 visibly reported `STATUS · HEALTHY` and `Fixture notifications are available`.
- Step 11 created one `ONBOARDING_TEST` prompt and visibly reported `RESULT · SCHEDULED`.
- The fixture recorded one delivered notification with category `ONBOARDING_TEST` and the same identifier as the canonical prompt episode.
- The running agent accepted the whitelisted `continue_intentionally` notification action.
- The persisted response surface is exactly `notification`.
- The onboarding UI refreshed to `PROMPT RESOLVED` and enabled Continue.
- Exit For Now opened Today with `SETUP IS PAUSED` and `Resume from deliveryTest`.
- Resume Setup returned to step 11 with the same resolved prompt.
- Quitting and relaunching the app restored step 11, the completed local test task, and the resolved canonical prompt.

Machine-readable proof is stored under `notification/`.

## Today fallback path

- A fresh QA root seeded notification permission as denied without touching the production notification center.
- Step 5 visibly reported `STATUS · ATTENTION`, `Fixture notification permission is unavailable`, and `No production notification center was touched`.
- Step 11 explicitly explained that notifications were not granted and that Today remains available for every coaching choice.
- Creating the canonical prompt visibly reported `RESULT · TODAY FALLBACK`.
- The unresolved prompt appeared in Today under Decisions with the same title, summary, Continue Setup action, and Use Today Instead action.
- Choosing Continue Setup from Today removed the prompt from Decisions and persisted a response with surface `dashboard`.
- Resume Setup returned to step 11 with `PROMPT RESOLVED` and enabled Continue.

Machine-readable proof is stored under `today-fallback/`.

## Automated gates

- `swift test --scratch-path .build/canonical-authoritative --parallel --num-workers 4` passed all 464 tests in five suites.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests -p "test_*.py"` passed all 41 tests.
- `python3 Scripts/scenario_registry.py validate` validated exactly 666 scenarios with no tracker drift.
- `swift build --configuration release --scratch-path .build/canonical-release` passed.
- The default and explicitly serialized Swift Testing execution paths can strand after all tests report success in an idle main run loop.
- The explicit four-worker SwiftPM execution path completed cleanly and is the authoritative full-suite gate for this run.

## Result

The canonical onboarding prompt is fully usable end to end through both supported delivery surfaces.

The prompt is agent-owned, idempotent per onboarding flow, restricted to harmless actions, durable across restart, resolvable from notifications or Today, and unable to bypass the required onboarding continuation gate.
