# Configurable intentional override verifier report

## Result

The intentional-gaming override duration is now a persisted Gaming Policy value exposed in Settings.
The runtime uses that saved value across service restart instead of a fixed 45-minute constant.

## Verification

- `swift test --filter SettingsPolicyDraftTests` passed.
- `swift test --filter GamingDriftPromptServiceTests` passed.
- The post-rebase configured-duration restart test passed with a 25-minute policy, suppression at 20 minutes, and reprompt after 26 minutes.
- Settings round-trip and conflict recovery preserve the duration independently and retain the winning value on overlap.
- Legacy Gaming Policy JSON without the field decodes to 45 minutes.
- Values below five minutes clamp to five, while a value above 1,440 minutes produces a policy validation violation on the exact field.
- `swift build -c release` passed after rebasing onto the authoritative root.

## Conservative acceptance boundary

The post-rebase package command did not produce the signed QA app bundle.
The signed Settings save/relaunch, Continue intentionally response, inside-window suppression, post-26-minute reprompt, unchanged gaming totals, and incomplete-task journey were therefore not run.
All three scenarios remain incomplete; only the newly implemented Settings scenario advances to `Touches remaining`.
