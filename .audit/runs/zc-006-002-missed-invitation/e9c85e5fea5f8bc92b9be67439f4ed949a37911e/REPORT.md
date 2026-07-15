# ZC-006-002 signed action acceptance

Status: PASS

The exact clean signed candidate was `e9c85e5fea5f8bc92b9be67439f4ed949a37911e`.
The package, code-signing identities, LaunchAgent, Mach service, writable XPC runtime, fixture, and bootstrap readiness checks passed.
The recovered invitation appeared once after the configured Cairo planning boundary had passed during the simulated inactive interval.
The exact foreground main window exposed one `WORK UNPLANNED` prompt action for prompt `31F1C97E-9298-4269-B3DB-9CB762E52FDB`.
Activating that action immediately rendered `LIMITED UNPLANNED MODE`, `Work without an approved plan.`, and the canonical no-drift copy.
The same prompt persisted as `responded` with one `work_unplanned` response on `dashboard` and one applied `PLAN_READY:work_unplanned` effect.
The helper restart did not create a second planning prompt.
An ordinary app relaunch retained the prompt-bound answered history and Work Unplanned choice, retained the canonical unplanned and no-drift UI, and exposed no actionable Work Unplanned control.
The private fixture sentinels were absent from every asserted invitation, action result, and relaunched state.
The isolated baseline was restored exactly by file hashes, metadata, and extended attributes before the scoped QA runtime was uninstalled.
The QA app, QA root, LaunchAgent job, and QA processes were absent after cleanup.
Production remained on app PID 29929 and agent PID 53195 with the required paths and binary hashes.

Focused PlanningInvitation and MissedPlanningInvitationRecoveryService tests passed.
The fixture, Accessibility, and signed-preflight self-tests passed.
Both release products built successfully at the final clean tip.

This immutable repository record accepts the functional signed evidence for ZC-006-002.
The signed source package is `/private/tmp/zoid-zc006002-evidence/e9c85e5fea5f8bc92b9be67439f4ed949a37911e-r1`.
