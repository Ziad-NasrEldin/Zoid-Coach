# Today Prompt Inbox Lifecycle Candidate

## Scope

This candidate implements a durable Today inbox timeline for `ZC-006-006`, `ZC-013-009`, `ZC-033-011`, `ZC-034-013`, `ZC-034-015`, `ZC-038-003`, `ZC-041-011`, and `ZC-053-007`.
It remains isolated from the authoritative tracker, registry, Lavish artifact, root branch, shared runtime, migrations, and notification delivery.

## End-user behavior

Today now separates decisions awaiting a response, snoozed decisions that will return later, and recent answered, dismissed, or expired decisions.
Each awaiting prompt retains every current action and adds an explicit Dismiss action.
Destructive or confirmation-required actions open a confirmation dialog before mutation.
Only one prompt mutation can be pending at a time, preventing duplicate clicks across prompt rows.
If an action loses a race with another surface, Today refreshes the canonical inbox and explains that the decision changed instead of applying stale UI state.
If the agent cannot refresh the inbox, the last confirmed timeline remains visible with a clear retry action.
Repeated episodes for the same decision are marked Returned so a recurrence is distinguishable from a duplicate surface.
Every inbox, section, row, action, dismissal, empty state, and retry control has a stable accessibility identifier.

## Persistence and state truth

The timeline is built by the agent-owned `PromptInboxStore` from canonical prompt episodes and responses.
Future `notBefore` episodes remain snoozed until their return time and then move into the actionable list without creating a duplicate episode.
Responded, dismissed, and timed-out episodes remain in bounded recent history.
Resolved decision keys can produce a later episode whose occurrence number survives database reopen.
The existing exactly-once response token and pending-effect transaction remain unchanged.

## Focused proof

`swift test --filter PromptInbox` passed all 11 selected tests on 2026-07-13.
The focused run compiled the application, agent, infrastructure, and test targets successfully.
New coverage proves waiting, snoozed, returned, answered, dismissed, expired, bounded recent history, invalid-limit rejection, and restart recovery.
Existing coverage in the same run proves one unresolved episode per decision, exactly-once concurrent response delivery, atomic effects, token binding, and deterministic fixture notification routing.

## Verification instructions

Rebase the candidate onto the newest authoritative root before verification.
Run `swift test --filter PromptInbox` once.
Use an isolated signed-QA root to seed one actionable prompt, one future `notBefore` prompt, one answered prompt, one dismissed prompt, and one timed-out prompt.
Verify the three visible sections, stable action labels, confirmation behavior, dismissal, stale-action refresh, and current state after app and agent restart.
Keep tracker statuses conservative until that installed journey passes.
