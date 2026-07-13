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

## Capped signed runtime result

- Installed app: `/private/tmp/zoid-666-notification-pref-install/Zoid 666 QA E2E.app`
- Isolated QA root: `/private/tmp/zoid-666-verify-notification-prompt-preference/.build/qa-notification-prompt-preference-verifier`
- The registered QA helper ran from the installed signed app with the exact QA LaunchAgent and Mach-service identity.
- Notification fixture permission was granted.
- The saved version-1 policy exposed `SEND COACHING PROMPTS AS NOTIFICATIONS` as on.
- One valid queued `GAMING_DRIFT` decision appeared visibly in Today while the fixture held its coaching notification and a separate `BREAK_END` notification.
- The signed Settings switch was turned off and saved through the live helper boundary.
- The saved policy advanced to version 2 with `notificationPromptsEnabled = false`.
- After one agent loop, the coaching notification was removed while the queued prompt remained in Today and the `BREAK_END` notification remained scheduled.
- The notification delivery ledger remained at zero rows, proving suppression did not create a false attempt or failure.
- After restarting both app and helper, policy version 2 remained disabled, the queued decision remained unresolved, and the break notification remained present.

## Conservative acceptance boundary

The hard runtime cap stopped the signed run before the final re-enable and resumed-delivery leg completed.
The focused coordinator test proves re-enable without restart in process, but this report does not claim the corresponding installed UI journey.
`ZC-039-008` therefore advances only to `Touches remaining`.

The tracker, registry, and Lavish artifact are synchronized after this report, and the signed QA runtime is removed during cleanup.
