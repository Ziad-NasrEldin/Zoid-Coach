# ZC-054-009 Candidate Report

## Outcome

Updated content for one logical coaching decision now uses the same privacy-safe macOS notification request identity across replacement prompt episodes.
After the new request is accepted, macOS replaces the old pending or delivered request directly instead of briefly retaining two episode-based requests.

## Identity Contract

- The logical decision key is hashed with SHA-256 and truncated to a fixed 128-bit hexadecimal identity.
- The raw decision key is never exposed to Notification Center.
- The transient prompt episode identifier is not exposed in the request identifier.
- Updated episodes for the same logical decision produce the same request identifier.
- Separate decisions produce separate request identifiers.
- Production and signed-QA notification namespaces remain isolated.
- An empty legacy decision key falls back to a deterministic hash of the episode identifier without exposing it.

## Compatibility

The notification content still carries the current prompt episode identifier privately for response routing.
Existing relevance-group cleanup removes older episode-based identifiers after the replacement is accepted, so upgrading does not leave obsolete notifications stacked.

## Verification

- `swift test --filter PromptNotificationCoordinatorTests` passed.
- Focused tests prove same-decision stability across different episode identifiers, different-decision separation, no raw-key or episode leakage, bounded identifier length, QA namespace isolation, and deterministic legacy fallback.
- `swift build -c release` passed.
- `git diff --check` passed before handoff.

## Remaining Acceptance

An independent verifier must schedule a real notification, update the same logical decision through a new episode, confirm Notification Center shows exactly one request with the newest content and actions, respond through the newest prompt identifier, relaunch, and confirm no obsolete notification returns.
Only the root integrator may update the authoritative tracker and registry after that verification.
