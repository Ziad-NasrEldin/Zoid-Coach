# Notification prompt preference verifier report

## Candidate

- Authoritative base: `292f34f`
- Original candidate: `2d97092`
- Clean cherry-pick: `5283e72`
- Scenario: `ZC-039-008`

## Independent verification result

No implementation blocker was found.
Legacy policy payloads without the new field resolve to enabled.
The Settings draft round-trips the toggle, and the conflict resolver preserves an independent toggle change alongside a concurrent policy edit.
The agent reads the latest persisted policy for every loop and notification scheduling decision, so disabling and re-enabling does not require a helper restart.
Disabling removes only prompt notifications while leaving unresolved prompt episodes available to Today.
Suppressed scheduling exits before permission checks and delivery-ledger recording, so it creates no false attempt or failure.
Accepted-break, task-start, review, and other non-prompt notification paths do not use this gate and are not removed by real Notification Center cancellation.
The QA fixture proof also preserves an accepted-break notification while removing coaching prompts.

## Automated evidence

- `git diff --check` passed.
- `swift test --package-path /private/tmp/zoid-666-verify-notification-prompt-preference --filter NotificationPromptPreferenceTests` passed all 3 focused tests.
- `swift test --package-path /private/tmp/zoid-666-verify-notification-prompt-preference --filter 'NotificationPermissionRecoveryTests|SettingsPolicyDraftTests|UserPolicyTests'` passed all 48 affected regression tests.
- One release QA package completed successfully.
- Package, LaunchAgent, Mach service, and signing identities are coherent.
- Packaged artifact: `/private/tmp/zoid-666-verify-notification-prompt-preference/.build/app-qa/Zoid 666 QA.app`

## Capped signed runtime sequence

This sequence is prepared but intentionally not executed until the shared runtime lease is assigned.

1. Install the verifier's signed QA artifact with its isolated QA root and start from granted notification permission.
2. Save notification prompts as enabled and create one unresolved coaching prompt.
3. Confirm the same prompt is visible in Today and has one fixture or Notification Center delivery.
4. Schedule an accepted-break end reminder as the non-prompt control.
5. Disable coaching prompt notifications through Settings and save through the helper boundary.
6. Wait for one agent policy loop, then confirm the coaching notification is removed while the Today row and accepted-break reminder survive.
7. Confirm the delivery ledger contains no new attempt or failure for a prompt created while disabled.
8. Restart the app and helper, then confirm the switch remains disabled and a new unresolved prompt appears only in Today.
9. Re-enable the switch without restarting, create a fresh prompt, and confirm notification delivery resumes while the Today row remains available.
10. Clean the isolated QA installation and preserve the evidence bundle for tracker integration.

The tracker, registry, backlog, Lavish artifact, and shared runtime were not changed in this verifier pass.
