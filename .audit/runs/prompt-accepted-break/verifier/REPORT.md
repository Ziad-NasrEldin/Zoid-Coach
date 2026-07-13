# Accepted Break Prompt Verification

## No-active blocker fixed

The candidate router safely produced no break effect when no task was active, but the gaming prompt still offered Take a break in that state.
An end user could therefore choose a visible action that only closed the prompt and changed nothing.

The verifier made Take a break conditional on a durable active task when the prompt is created.
If the active task disappears before a stale notification or Today surface responds, the router still resolves safely without inventing a pause.

## Durable behavior

For an active task, Take a break closes its active interval at the response time and appends the canonical `break` pause reason.
The gaming-drift gate consumes that open pause as `acceptedBreak`.
The router uses the actual active task rather than blindly pausing the priority task named by the prompt.
Same-token replay produces no second task mutation.
Normal Resume closes the pause, after which ordinary coaching eligibility applies again.

## Proof

- The prompt response router focused group passed.
- The accepted-break gaming gate passed.
- After the no-active fix, the complete gaming-drift and router focused groups passed.
- One release build passed.
- `git diff --check` passed.

## Signed acceptance

The installed signed app showed one active tracked task and one gaming prompt with Take a break.
Choosing it visibly changed Today to `PAUSED FOR A BREAK`, retained neutral `for a break` copy, resolved the prompt into Answered history, and produced exactly one response, one open break pause, and one paused execution state.

After terminating both app and helper, launchd started a new helper PID and the relaunched app restored the same paused break and answered prompt history.
Resume returned the task to Active commitment and closed the open break.

A simultaneous installed notification replay was not available in the seeded fixture.
Focused same-token replay proof remains the evidence for duplicate-effect prevention.
