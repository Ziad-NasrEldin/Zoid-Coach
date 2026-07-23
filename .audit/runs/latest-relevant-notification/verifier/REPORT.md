# Latest Relevant Prompt Notification Verification

## Decision

`ZC-038-007` and the notification-replacement portion of `ZC-033-011` move to Touches remaining.

The relevance policy, replacement ordering, group independence, durable Today preservation, and exactly-once response behavior passed focused and installed signed-QA verification.

Real macOS Notification Center remains unverified because signed QA mode intentionally routes prompt notifications through its isolated deterministic OS fixture.

## Integrated lineage

The implementation is `effd6d0` and the accept-before-remove correction is `3de19b2`, both rebased onto authoritative baseline `adaf7f6`.

The single validated QA package was produced before that clean rebase and identified itself as `zoid-coach-16b78e3311aea5f32327adf8519ed3e3e2496195-clean`.

The rebase had no source overlap with the notification implementation.

## Focused verification

One combined relevance, coordinator, notification-preference, and same-prompt replacement run passed.

After inspection found premature same-identifier removal in the real macOS path, the coordinator was corrected to keep the last accepted notification until `UNUserNotificationCenter.add` accepts its replacement.

The affected same-prompt replacement seam passed once after that correction.

The focused proof covers plan-ready to plan-changed grouping, independent meeting and gaming groups, latest gaming replacement, unresolved Today preservation, same-prompt content replacement, preference disable and re-enable, and deterministic response idempotency.

## Release verification

Exactly one release QA package completed successfully.

App and helper release builds, package coherence, signing identities, LaunchAgent, Mach service, on-disk signature, and designated requirement all passed.

The normal signed-app registration handshake succeeded once.

## Signed installed verification

The deterministic notification state contained only the latest plan-changed notification, the independent meeting notification, and the latest gaming notification for the owned relevance groups.

Today simultaneously displayed all five unresolved decisions, including the superseded earlier plan and earlier gaming decisions.

The older gaming decision was answered from Today once.

The canonical database contained exactly one response for that decision, four queued episodes, and one responded episode.

The latest plan, meeting, and gaming notification records remained unaffected.

After terminating and relaunching both the installed app and helper, Today retained four waiting decisions and one answered older decision.

## Remaining touch

The isolated QA adapter deliberately does not populate the user's real Notification Center.

One safe non-QA acceptance run must still confirm the same latest-per-group result in Notification Center before either scenario can be marked Fully implemented.
