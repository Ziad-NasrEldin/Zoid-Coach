# Notification prompt preference candidate report

## Scope

This candidate implements scenario `ZC-039-008`, which lets a user disable coaching prompt notifications without losing access to unresolved coaching decisions in Today.

The preference defaults to enabled for existing and legacy policy payloads.

The Settings notification-delivery section exposes a labeled switch, persistent explanatory copy for both states, and stable accessibility identifiers.

The Settings draft persists the preference and the conflict resolver preserves an independent notification change during concurrent policy edits.

The agent reads the latest saved preference dynamically, so delivery can stop or resume without restarting the helper.

When the preference becomes disabled, the agent removes already pending and delivered coaching-prompt notifications.

The cancellation targets coaching prompts only and leaves task-start, break-end, review, and other non-prompt notification services untouched.

Suppressed prompt delivery does not create a misleading delivery-ledger failure or attempt.

Prompt episodes remain unresolved in `PromptInboxStore`, which preserves their existing Today-dashboard access.

## Automated evidence

`swift test --filter NotificationPromptPreferenceTests` passed all 3 focused tests.

The focused tests cover legacy defaulting, Settings round-trip persistence, concurrent Settings conflict preservation, cancellation of an existing prompt alert, survival of a scheduled break alert, continued in-app prompt availability, no false ledger event, and notification resumption without restarting the coordinator.

`swift test --filter 'NotificationPermissionRecoveryTests|SettingsPolicyDraftTests|UserPolicyTests'` passed all 48 affected regression tests.

`swift build -c release` completed successfully.

`git diff --check` completed successfully.

## Verifier plan

The verifier should first rebase this candidate onto authoritative commit `292f34f` or the newer authoritative tip.

The verifier should rerun the focused and affected automated tests after the rebase.

The verifier should acquire the runtime lease and install a signed QA build.

The verifier should start with granted notification permission and at least one unresolved prompt.

The verifier should confirm that the enabled preference produces a macOS notification and a Today row for the same prompt.

The verifier should disable the switch in Settings and save through the real helper boundary.

The verifier should confirm that the existing coaching notification is removed while its Today row remains usable.

The verifier should confirm that disabling the preference adds no false delivery-ledger failure.

The verifier should restart both the app and helper, confirm that the preference remains disabled, and confirm that a new coaching prompt appears in Today without a macOS notification.

The verifier should schedule a non-prompt break or review notification and confirm that it remains unaffected.

The verifier should re-enable the switch, save without restarting, and confirm that a newly queued coaching prompt resumes macOS notification delivery while remaining available in Today.

The tracker should change only after the signed runtime proof is captured.
