# Prompt Action Feedback Verification

## Truth blocker fixed

The candidate originally promised that every open surface would refresh after a response.
The durable prompt store and deterministic response token prevent duplicate responses and effects, but response handling does not actively withdraw or refresh an already delivered notification.

The verifier changed the progress and confirmation copy to promise only what the product guarantees.
Today refreshes from the durable result, while an older notification or other surface cannot apply the same action twice.

## Durable behavior

The selected Today row alone shows Applying.
All Today prompt actions are disabled during the in-flight write.
The XPC boundary writes the response before returning, the effect router is idempotent, and the prompt store rejects conflicting token reuse.
Replay and restart tests retain one response and one applied effect.

## Proof

- `swift test --filter PromptActionPresentationTests` passed after the copy fix.
- `swift test --filter PromptInboxTests` passed.
- One release build passed.
- `git diff --check` passed.

## Signed acceptance boundary

The one permitted package/install attempt exited with status 1 and no diagnostic output before creating an installed app or registering a QA helper.
No retry was performed under the package-once and UI cap.

The installed Today and notification same-token race, notification stale-state behavior, and app/helper restart therefore remain unverified.
Both mapped tracker scenarios remain conservative.
