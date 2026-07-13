# Active-task context candidate report

## Candidate

- Baseline: `f46cad3`
- Claim commit: `aa970f3`
- Implementation commit: `f053e4a`
- Scenarios: `ZC-018-004`, `ZC-018-005`

## End-user result

When a task is active, Today now shows one compact context assessment beside the active commitment.
Fresh work-classified evidence appears as `Context looks work-aligned` and explicitly says that this is a signal rather than proof of task alignment.
Fresh gaming or distracting evidence appears as `Context may not match this task` without productivity labels or blame.
Idle, unknown, missing, and stale evidence appears as `Context is uncertain`, and the copy states that Zoid 666 will not guess.
No context assessment is shown when there is no active task.

## Implementation evidence

- `ActiveTaskContextAssessor` maps the freshest observation into aligned, uncertain, or mismatched states with a 15-minute freshness boundary.
- `TodayDashboardAgent` computes the assessment only for an active task and includes it in the persisted Today snapshot.
- `TodayDashboardCommandOverview` renders the assessment in the active focus card with a combined accessibility element and stable identifier `today.focus.context-assessment`.
- Existing snapshot initializers remain source-compatible because the new context field defaults to `nil`.

## Verification completed

- `git diff --check` passed.
- `swift test --package-path /private/tmp/zoid-666-fresh-after-time-zone --filter 'TodayDashboardTests|TodayDashboardAgentTests'` passed.
- The focused tests cover fresh work, fresh gaming, unknown, missing, stale, no-active-task, and active-task-with-missing-evidence states.
- Release QA packaging passed with coherent app, LaunchAgent, Mach service, and signing identities.
- Packaged artifact: `/private/tmp/zoid-666-fresh-after-time-zone/.build/app-qa/Zoid 666 QA.app`

## Verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative integration head and rerun the two focused suites.
2. Install the signed QA app with an isolated QA root.
3. Start a planned task and verify the active focus card exposes `today.focus.context-assessment`.
4. Seed or ingest a fresh work observation, refresh Today, and verify aligned copy plus the `signal, not proof` caveat.
5. Seed or ingest fresh gaming evidence, refresh Today, and verify neutral mismatch copy with no judgmental productivity wording.
6. Age the last observation beyond 15 minutes, refresh Today, and verify the state becomes uncertain rather than retaining the prior conclusion.
7. Restart the app and agent, then confirm the current assessment is reconstructed from durable evidence without duplicate UI.
8. Stop the task and verify the context assessment disappears.

The tracker and scenario registry remain verifier-owned and were not changed by this candidate.
