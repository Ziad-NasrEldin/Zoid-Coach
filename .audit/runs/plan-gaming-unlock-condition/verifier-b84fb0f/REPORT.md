# ZC-008-016 gaming unlock verification

## Scope

This verifier started from authoritative commit `b84fb0f4dfa2e25e36a78915cfc332eade14c4b5` in a fresh isolated worktree.
The canonical tracker and registry still classify changing the gaming unlock condition as `Not implemented`.

## Existing implementation inspection

The plan uses the product's canonical unlock rule: completing today's main objective earns the configured one-time gaming reward.
When that reward is locked, the current main objective names the exact locked minutes.
Every other planned task changes its existing Make Main control to `MAKE MAIN + GAMING UNLOCK`.
The control's accessibility hint explains that the main objective and reward condition move together.
Activating the control opens a confirmation that names the selected task, exact reward minutes, and replacement consequence.
Cancel performs no mutation.
Confirm uses the existing main-objective mutation, which keeps exactly one main objective and persists the plan through the agent-owned plan boundary.
The special unlock wording disappears when budgeting is disabled, the configured reward is zero, or the reward was already earned.

## Related gaming classification evidence

Existing signed acceptance proves that Settings exposes Automatic, Work, Communication, and Gaming application rules, persists an explicit rule through app relaunch, and safely resets it to Automatic after destructive confirmation.
Existing signed Daily Review acceptance proves that a user can correct a session, optionally create a future rule, preserve that rule across app relaunch, and retain historical evidence when removing the future rule.
Existing contextual-classification acceptance proves clear local signals can produce Work, Gaming, or Distracting while ambiguous context remains Unknown.
The signed Review surface exposes application, time range, duration, observation count, classification, and task attachment without exposing window titles, URLs, screenshots, or captured content.

## Deterministic verification

One focused command passed nine selected tests covering the exact Gaming Unlock presentation states, durable plan shape, reward application across agent reconstruction, future-rule persistence and removal, unsafe Idle and Unknown rule rejection, contextual classification with ambiguous Unknown, and explicit policy precedence.
The release build completed successfully.
No product failure was observed.

## Verification pending

The signed installed plan journey still needs native Accessibility and pixel proof using the current signed-window procedure rather than the invalid empty-window oracle used by the older verifier.

## Current classification

The exact current canonical status is `Not implemented`.
Static inspection and fresh deterministic evidence support `Touches remaining` until the signed installed journey passes.
