# Today Prompt Inbox Lifecycle Verification

## Result

The candidate provides a durable prompt timeline with awaiting, snoozed, and recent states, user actions, dismissal, expiry, bounded history, stale-state refresh, and restart recovery.

The verifier found and fixed one release-blocking usability defect.
The shared Today inbox exposed Dismiss for mandatory onboarding prompts, which could permanently strand setup.
Dismissal is now explicitly opt-in per prompt, the store rejects dismissal for mandatory prompts, and Today hides the unavailable control.

## Proof

- `swift test --filter PromptInbox` passed before the verifier fix.
- `swift test --filter promptInboxRefusesToDismissAMandatoryDecision` passed after the verifier fix.
- The release build completed and produced the signed QA artifact.
- Deep signing, helper registration, helper health, and installation passed for `/private/tmp/zoid-prompt-inbox-apps/Zoid 666 QA E2E.app`.
- The installed app opened Today and visibly rendered the `DECISIONS` inbox with a Refresh control.

## Remaining acceptance

The isolated fixture database contained one dismissible prompt and one mandatory prompt, but the installed helper returned `Decisions could not be refreshed` instead of loading the seeded rows.
The verifier stopped at that environmental boundary and did not claim live action, dismissal, stale refresh, or restart persistence.
Behavior-coaching generation, daily-review presentation, notification-disappearance recovery, and a healthy installed helper fixture journey remain required.
