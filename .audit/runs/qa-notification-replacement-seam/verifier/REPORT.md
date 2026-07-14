# ZC-054-009 Final Notification Center QA Seam Verification

## Current verdict

The canonical scenario remains unchecked at **Touches remaining**.

The candidate now has a signed-QA-only visible seam and deterministic proof through the real `PromptNotificationCoordinator` contract.

Actual Notification Center one-card replacement, newest-action routing, and relaunch non-resurrection remain required before promotion to **Fully implemented**.

## Revision boundary

- Authoritative baseline: `d129596190ebb1d2eb8d132fee4371e2576e5661`.
- Candidate source commits: `b011d087585ad20770f95b30c347099832ecc043` and `60149484bec2267101839b3a364aede046f36cc9`.
- Candidate transplant commits: `ac6bd26` and `7811b61`.
- Verification branch: `codex/verify-final-notification-center-seam`.
- Backlog, tracker, registry, Lavish, production coordinator, and notification persistence files were not edited.

## Guard and production-path review

- The probe is available only when runtime mode is QA, package mode is QA, and the resolved runtime identity is the QA identity.
- Production and unpackaged QA environments fail closed before constructing a prompt store, coordinator, or visible control.
- The visible controller creates `PromptNotificationCoordinator` without a fixture adapter, activates it as the real notification-center delegate, and therefore exercises `UNUserNotificationCenter` in a signed QA package.
- The stable request identifier is derived from a private SHA-256 digest of the logical decision key and does not reveal the raw key or episode identifier.
- Probe titles, summaries, identifiers, and actions are generic and contain no captured activity, task titles, file paths, or private user content.
- Create, replace, refresh, status, and containing-group accessibility identifiers are stable and the button text communicates the sequence without relying on color.

## Independent repair

The candidate changed action titles only in stored `PromptAction` metadata while both phases used the static `ONBOARDING_TEST` macOS category.

Notification Center would therefore replace the title and body but continue showing the same `Continue Setup` and `Use Today` actions.

The verifier changed the original episode to the real `PLAN_READY` category and the replacement episode to the real `PLAN_CHANGED` category.

The logical decision key and private request identifier remain identical, while the production category changes from Accept, Plan now, Snooze, and Dismiss to Review and Undo.

The newest routed action is now `undoPlanChange`, which is valid only for the replacement category.

## Deterministic proof

- The baseline focused invocation `swift test --filter "QANotificationReplacementProbeTests|PromptNotificationCoordinatorTests"` passed 11 selected tests.
- The repaired focused invocation passed the same 11 selected tests at exit 0.
- Production and unpackaged QA refusal remain covered.
- The original and replacement use different episode identifiers, titles, summaries, categories, and action sets while retaining one logical decision and one stable private request identifier.
- Fixture delivery contains exactly one record with the newest prompt identifier, `PLAN_CHANGED` category, title, and body.
- Only the replacement episode receives the `undoPlanChange` notification response.
- A reconstructed store, adapter, coordinator, and probe restore the newest episode and durable response without resurrecting the obsolete notification.
- `git diff --check` passed.

## Release-build disk guard

The sole incremental release build started with 594 MiB free.

Free space fell below the orchestrator's 400 MiB safety floor before completion, so only that build was interrupted at exit 130 and only this verifier worktree's reproducible `.build` directory was removed.

The release build is not claimed as green for the verifier repair.

## Remaining signed acceptance

1. Confirm that notification permission is already authorized for the isolated QA bundle without changing System Settings or approving a prompt.
2. Create the original plan-ready notification and inspect one card with the original title, body, and actions.
3. Replace it and inspect exactly one card with the updated title, body, and plan-changed actions.
4. Invoke Undo from the newest card and prove the response belongs only to the replacement episode.
5. Restart app and helper and prove the response remains durable and the original card does not return.

No runtime lease should be requested until the repaired release build completes successfully with safe disk headroom.
