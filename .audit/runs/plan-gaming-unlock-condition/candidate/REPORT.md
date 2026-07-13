# Plan Gaming Unlock Condition Candidate Report

`ZC-008-016` is ready for independent signed verification.
The candidate exposes the product's existing canonical rule: completing today's main objective earns the configured one-time gaming reward.

## End-user behavior

When a reward is still locked, the current main objective displays `GAMING UNLOCK - COMPLETE THIS TASK FOR N MIN` with a task-specific accessibility identifier.
Every other planned task changes its existing Make Main control to `MAKE MAIN + GAMING UNLOCK`.
Its accessibility hint explains that both the main objective and reward condition move together.

Activation does not mutate the plan immediately.
A confirmation names the selected task, the exact reward minutes, and the fact that it replaces the current main objective as the condition.
Cancel preserves the existing plan.
Confirm uses the existing `setMainObjective` mutation, so there remains exactly one durable main objective and the completion reward path follows the newly selected task.

The extra unlock wording is absent when gaming budgeting is disabled, when no reward is configured, or after the reward has already been earned.
The ordinary Make Main behavior remains unchanged in those states.

## Focused proof

`GamingUnlockConditionPresentationTests` covers a locked 25-minute reward, the exact current-condition label, the deliberate move label, the consequence-first confirmation copy, disabled budgeting, and an already-applied reward.
`swift test --filter GamingUnlockConditionPresentation` passed.
`swift build -c release` passed.

## Independent signed acceptance

Start with a two-task plan and a non-zero locked priority reward.
Confirm the main objective names the exact gaming unlock and the other task offers `MAKE MAIN + GAMING UNLOCK`.
Open the move confirmation and cancel, then confirm the original main objective and unlock label remain unchanged.
Open it again, confirm the move, and verify exactly one main objective plus the unlock label moves to the selected task.
Restart the app and helper and confirm the same condition remains.
Complete the old task and confirm no reward appears.
Complete the newly selected main objective and confirm the configured one-time reward appears exactly once.
