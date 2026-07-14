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

The signed installed plan journey used the current native Accessibility and pixel-backed procedure rather than the invalid empty-window oracle used by the older verifier.

## Signed installed acceptance

The canonical signed QA package installed with a running helper in an isolated QA and install root.
The first two-reminder fixture was rejected because its second Reminder priority was outside the fixture's supported values, and the visible safety mode correctly blocked mutations.
After correcting only that temporary fixture value, the signed app opened a valid ready state with two visible reminders.
Today visibly showed `Locked 15m` and explained that finishing one priority task unlocks a one-time reward.
Drafting the suggested plan created two visible planned blocks and exactly one main objective.
The reachable non-main task control said `MAKE PREPARE LAUNCH BRIEF THE MAIN OBJECTIVE`.
Native Accessibility inspection of the complete Today scroll surface did not expose `MAKE MAIN + GAMING UNLOCK`, a task-specific gaming unlock condition label, or the `Move unlock condition` confirmation.
The source-only `PlannedReminderRow` presentation therefore was not reachable through the actual Day Map task controls exercised by the user.
Because the required control was absent, Cancel, confirmed reassignment, app and helper relaunch persistence, old-task completion without reward, and new-main exactly-once reward could not be exercised.
The runtime was uninstalled and the lease was released without touching shared product data.

## Remaining product gap

The gaming unlock presentation must be wired into the task controls that Today actually renders for a drafted plan.
That reachable control must then pass the complete signed Cancel, move, relaunch, and reward-consequence journey.

## Current classification

The exact current canonical status is `Not implemented`.
The recommended status remains `Not implemented` because the required end-user control is absent from the reachable signed Today journey even though disconnected presentation code and focused tests exist.
