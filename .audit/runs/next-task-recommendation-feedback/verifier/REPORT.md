# Next-task recommendation feedback verifier report

## Decision

`ZC-015-006` advances to Fully implemented.
`ZC-015-007` and `ZC-015-008` advance to Touches remaining.
The signed cap completed one successful Not Now journey, durable alternate selection, app and helper restart persistence, and one truthful Wrong Priority outage failure.
Wrong Priority and Too Large successful installed activation, keyboard-only activation, and visible next-day release remain unclaimed.

## Lineage

- Authoritative base: `db7db53`.
- Rebased candidate: `a1d7bb6`.
- Independent regression fix: `9978b5a0288a96bf484910e068ee22bd90a73a28`.
- Installed build identity: `zoid-coach-9978b5a0288a96bf484910e068ee22bd90a73a28-clean`.

## Focused verification

The combined RecommendationFeedback and TodayDashboardAgent filter ran seventeen tests once.
All recommendation-feedback tests passed.
The run exposed one real cross-feature regression: the coaching-specific three-secondary-action cap rejected the existing five-action planning invitation and broke unplanned work.
The verifier scoped that cap to explicitly contracted behavior prompts, retained strict behavior-prompt rejection, and reran only the failed unplanned-work seam and behavior-cap test successfully.

The focused tests prove all three encoded feedback choices, request idempotency, conflicting replay rejection, the five-minute mutation freshness boundary, canonical domain-event persistence, alternate selection, thirty-minute Not Now expiry, same-policy-day Wrong Priority and Too Large suppression, next-day release, and agent-restart restoration.

## Static safety review

Feedback writes travel through the authenticated background-agent mutation boundary.
The agent records a local domain event with the request identifier, task identifier, exact feedback kind, recommendation sentence, local day, timezone, and occurrence time.
Recommendation selection filters only the durably suppressed task identifiers before applying the existing deterministic ranker.
No feedback path changes task estimates, plan membership, completion, blocked state, or creates a task split.
Mutation failure preserves the current recommendation and directs the user to Agent source health.
A successful mutation followed by refresh failure distinguishes saved feedback from stale presentation and asks the user to refresh Today.

## Release and package proof

The release app build passed.
One QA package passed package, LaunchAgent, Mach-service, nested-signing, on-disk signature, and designated-requirement validation.

## Signed acceptance

The installed signed app loaded three ready planned tasks: `Ship urgent proposal`, `Review client notes`, and `Organize project archive`.
Today displayed one current recommendation while retaining the complete plan.
The current recommendation exposed Not Now, Wrong Priority, and Too Large as native buttons with stable accessibility identifiers and exact explanatory hints.

Activating Not Now produced the visible confirmation `Not now recorded. Zoid 666 will choose another ready task for the next 30 minutes.`
The recommendation changed from `Organize project archive` to `Review client notes` without changing task estimates, plan membership, or completion state.
After quitting and relaunching the app and killing and relaunching the registered helper, Today restored `Review client notes` as the current alternate within the suppression window.

The verifier then unregistered and stopped the signed helper and activated Wrong Priority.
Today kept `Review client notes` active and visibly reported `Feedback was not saved. The current recommendation is still active. Check Agent source health and try again.`
No Wrong Priority event was persisted during the outage.

## Remaining signed acceptance

1. Activate Wrong Priority successfully and visibly retain its alternate across same-day app and helper restarts.
2. Advance across the policy-local day and visibly confirm the original task becomes eligible again.
3. Activate Too Large successfully and visibly prove estimates, task state, and plan membership remain unchanged.
4. Traverse all three controls through keyboard-only focus and activation and inspect the transient progress state.
