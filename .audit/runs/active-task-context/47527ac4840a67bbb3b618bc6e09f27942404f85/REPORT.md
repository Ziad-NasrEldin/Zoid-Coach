# Active task context verifier report

## Verified revision

- Authoritative base: `40b1490`.
- Verified implementation: `47527ac4840a67bbb3b618bc6e09f27942404f85`.
- Installed build identity: `zoid-coach-47527ac4840a67bbb3b618bc6e09f27942404f85-clean`.

## Automated verification

- The combined `TodayDashboardTests|TodayDashboardAgentTests` filter passed once before the final authoritative rebase.
- The time-zone delta touched only Settings policy views and tests, so the passing Today dashboard seam did not require a duplicate run.
- Focused coverage passed no-active-task suppression, active missing evidence, fresh work, fresh gaming, unknown, stale, neutral wording, and the signal-not-proof rule.
- One authoritative rebased QA package passed with coherent app, LaunchAgent, Mach service, and signing identities.
- `codesign --verify --deep --strict` passed on the installed isolated app.

## Signed installed acceptance

- The signed user created and started `Verify active context` as a durable local task.
- With no observation, the active focus card visibly rendered `CONTEXT IS UNCERTAIN` and stated that Zoid 666 would not guess.
- A fresh durable Xcode observation classified as work visibly rendered `CONTEXT LOOKS WORK-ALIGNED` and the exact caveat `This is a signal, not proof that it matches this task.`
- Relaunch preserved the same active task and reconstructed the aligned assessment from durable evidence.
- A newer durable Steam observation classified as gaming visibly rendered `CONTEXT MAY NOT MATCH THIS TASK` and the neutral instruction to check context before changing the plan.
- Aging the latest evidence beyond fifteen minutes visibly rendered `CONTEXT IS UNCERTAIN` and stated that the evidence was stale, so Zoid 666 would not guess.
- The assessment appeared only inside the active commitment card and kept all normal task controls available.

## Result

- `ZC-018-004` is fully implemented.
- `ZC-018-005` is fully implemented.
