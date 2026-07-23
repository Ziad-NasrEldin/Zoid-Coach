# Prompt blocker reachability verification

## Decision

`ZC-034-011` remains Touches remaining.

The candidate improves visual ordering, but the signed installed app still exposes empty accessibility collections for both task-changing and recovery actions.
`Mark blocked` therefore remained unreachable through accessibility in the constrained Today window, so the blocker sheet and durable mutation journey were not accepted end to end.

## Verified lineage

Candidate `eac6c18` was cherry-picked and then rebased once onto authoritative commit `15c5464` as `e7030f585f1c67db9654ead7d4532837bba5f4bf`.
The post-rebase release QA package passed app, helper, signing, and designated-requirement coherence.

## Focused proof

One `swift test --filter PromptTaskBlockState` invocation passed.
It covered the exact six-action partition without duplicate identifiers and the trimmed 3-to-240-character blocker reason boundary.

## Signed runtime result

The exact installed signed app and helper ran with isolated QA state.
The fixture contained `Ship client proposal` as the active main task, `Prepare launch notes` as the ready replacement, and one presented `GAMING_DRIFT` envelope with six numeric `requiresConfirmation` flags.
SQLite confirmed one presented prompt, six decoded actions, zero responses, and the original task still active and main.
The constrained Today window rendered `DECISIONS 1 WAITING`, the prompt title and summary, and the new `CHANGE THE TASK` label before `RECOVERY OPTIONS`.
The accessibility tree exposed `today.prompt.qa-block-1.task-change-actions` as a collection with only scroll actions and no button children.
The recovery collection likewise exposed no actionable children.
No coordinate guess or substitute task-row action was used.

## Unaccepted acceptance steps

The signed run did not open the focused reason sheet, reject a two-character reason, prove Cancel preservation, save a meaningful blocker, promote the replacement main task, move the prompt to answered history, prove relaunch durability, or exercise the unavailable-agent failure path.
Those steps remain required after the task-change buttons become directly accessibility reachable.

## Cleanup

The signed QA app and helper were stopped and unregistered.
The isolated installed app, QA state, and fixture were removed.
`launchctl` confirmed that `qa.ziadnasreldin.ZoidCoach.agent` was absent before the runtime lease was released.
