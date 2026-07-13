# Coach-prompt accepted break candidate

## Outcome

Choosing `Take a break` from a gaming coaching prompt now pauses the actual active task with the durable `break` reason instead of only resolving the prompt.

## End-to-end behavior

- The response router accepts `start_break` only for a gaming-drift prompt.
- It resolves the currently active task rather than blindly pausing the unfinished priority task named in the prompt payload.
- The active interval closes at the factual response time.
- The task becomes paused with `TaskPauseReason.break`.
- The durable open break pause is the same state the gaming-drift gate already suppresses as `acceptedBreak`.
- Replaying the same notification or Today response does not mutate task execution again.
- The existing Return-to-task response now also checks `wasApplied` before mutation, removing the same replay risk.
- If no task is active, the prompt still resolves without inventing a task break.

## Verification

- `swift test --filter PromptResponseEffectRouterTests` passed.
- `swift test --filter gamingPromptBreakActionPausesTheActiveTaskExactlyOnce` passed.
- The focused journey starts an active task, responds from notification, replays from Today, confirms one applied effect, confirms no active task, and confirms durable paused state with reason `break`.
- Existing gaming-drift focused coverage proves an open `break` pause suppresses coaching with `acceptedBreak`.
- `git diff --check` passed.

## Acceptance boundary

The candidate does not claim signed notification or Today interaction.
A fresh verifier should seed an active task and gaming prompt in signed QA, choose Take a break from one surface, confirm the task pauses with neutral break copy, replay from the other surface, verify no duplicate effect, and confirm qualifying gaming remains free from drift prompts until Resume.
