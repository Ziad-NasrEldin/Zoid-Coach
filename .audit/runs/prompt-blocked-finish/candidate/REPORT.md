# Prompt Blocked Finish Candidate Report

## Scope

This candidate finishes the visible `ZC-034-011` prompt-action and blocker-form surface without changing the durable mutation or response routers.
It is based on authoritative commit `da1d82244fcc69f2230d0f4eedfbc79c18985290`.

## Reproduced gap

The existing focused tests proved action partitioning and reason length only.
They did not define or exercise a public contract requiring every coaching choice to be a direct keyboard and accessibility control.
The current view still rendered recovery actions inside an adaptive `LazyVGrid`, the same virtualized collection class that previous signed runs exposed without actionable children.
The blocker form accepted only free text, had no explicit local duplicate-submission state, and answered history did not show the saved blocker reason.

The red command was `swift test --filter PromptTaskBlockStateTests` after adding public-interface and form-state regression cases.
It failed against the missing direct-button interface, blocker form state, reason suggestions, and history reason lookup.

## Implementation

Every task-change and recovery action now renders as a direct full-width button in the prompt row.
No coaching action is nested in a lazy or virtualized collection.
Every direct control receives a deterministic `today.prompt.<prompt-id>.action.<action-kind>` accessibility identifier from the same tested public-interface model used by the view.

The blocker sheet offers three valid common reasons as direct buttons and keeps the focused free-text editor for custom reasons.
The form trims input and enforces the existing 3-to-240-character contract.
The form sets a synchronous local submission guard before the async mutation begins, so rapid repeated activation cannot start a second confirmation.
Cancel clears the local form without calling the mutation path.
Mutation failure clears the busy state and leaves a visible, accessible retry explanation while the coaching decision remains open.

Answered `Mark blocked` history now shows the blocker reason loaded from the durable daily plan.
This gives the end user a truthful visible reason after the app reloads the same persisted plan.

## Focused contract

The focused suite covers all six actions, their order, their stable identifiers, and the direct-button presentation contract.
It covers empty-input rejection, trimmed valid input, repeated-submit rejection, failure recovery, and Cancel reset.
It validates every selectable reason and the durable-plan-to-history reason lookup.

The combined focused command passed 10 tests with zero failures.
The production release build passed.

## Remaining verification

The candidate still requires the coordinated release build and one signed installed journey.
That journey must prove native accessibility reachability, invalid input, Cancel preservation, one successful block, replacement-main promotion, exactly one answered decision, visible Today and history reason, app and helper relaunch durability, and helper-unavailable failure preservation.
