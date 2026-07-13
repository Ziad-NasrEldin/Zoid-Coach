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

## Signed acceptance pending

The serialized signed runtime remains owned by the source-repair verifier.
A later capped run should race the same action token from Today and notification, confirm one response and one effect, and inspect truthful resolved state after app and helper restart.
