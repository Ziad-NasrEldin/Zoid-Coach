# Prompt Blocker Reachability Candidate Report

`ZC-034-011` is ready for a repeat signed installed journey.
The candidate addresses the prior capped session in which all six actions existed but Mark blocked sat at the lower edge of the constrained Today window and the blocker sheet could not be opened reliably.

## End-user behavior

The prompt card now separates task-changing actions from recovery options.
Reschedule and Mark blocked appear once each in a dedicated `CHANGE THE TASK` group directly below the prompt summary.
The longer return, sprint, break, and continue controls remain in `RECOVERY OPTIONS` below them.
This keeps the complete six-action contract without duplicate controls and makes the destructive task actions reachable before the lower recovery grid.

The Mark blocked control retains its stable identifier and now explains that it opens a reason sheet and leaves the coaching decision waiting until the blocker is saved.
The sheet focuses the reason editor when it opens, states the 3-240 character requirement visibly, adds the same requirement as an accessibility hint, and gives Cancel a stable identifier.
The existing validation, failure preservation, ordered task mutation, replacement-main promotion, and prompt resolution behavior remain unchanged.

## Focused proof

`PromptActionReachabilityLayout` deterministically partitions the exact six-action gaming-drift envelope into two task-changing actions and four recovery actions.
The focused test proves original relative order, complete coverage, and no duplicate identifiers.
The existing reason test continues to prove whitespace trimming plus the exact 3-to-240-character boundary.

`swift test --filter PromptTaskBlockState` passed.
`swift build -c release` passed.

## Independent signed acceptance

Load the exact six-action numeric-flag gaming-drift fixture in a constrained Today window.
Confirm Mark blocked is visible and accessibility reachable directly below the summary without first scrolling the recovery grid.
Open it by accessibility activation or keyboard focus.
Submit a too-short reason and confirm the error leaves the prompt and task unchanged.
Cancel and confirm the prompt and active task remain unchanged.
Reopen, save a meaningful reason, and confirm the original task becomes blocked, its active interval closes with the blocker reason, the ready task becomes main, and the prompt moves once to answered history.
Restart the app and helper and confirm the resolution persists.
Finally repeat with the helper unavailable and confirm the task and prompt remain unchanged with a usable retry message.
