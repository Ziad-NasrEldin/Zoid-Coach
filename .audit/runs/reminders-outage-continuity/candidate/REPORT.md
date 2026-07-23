# Reminders outage continuity candidate

## Scope

- `ZC-051-001` - Continue manual planning after Reminders access is denied or revoked.
- `ZC-051-004` - Keep local estimates, active sessions, and plan state while sync is unavailable.

## End-user result

Today now shows a dedicated continuity banner whenever Reminders is denied, disconnected, unavailable, or requires attention.
The banner reports the exact retained planned-task count and estimated minutes from the canonical Today snapshot.
When a task is active, it explicitly confirms that tracking continues locally.
It explains that the local plan and history remain on the Mac and avoids implying that Apple synchronization succeeded.
The user can create a local task immediately or open Source Health to repair Reminders.
Both actions and the banner have stable accessibility identifiers.
The banner disappears when Reminders is healthy.

## Evidence

- Candidate implementation: `8a49afb`.
- `swift test --filter RemindersOutageContinuityTests` passed all three new truth-state tests.
- `swift test --filter LocalTaskCreationControllerTests` passed the real SQLite local-task creation, idempotency, plan inclusion, and restart coverage.
- `swift test --filter TodayDashboardAgentTests` passed the canonical Today snapshot, local task, execution, and persistence coverage.
- `git diff --check` passed before the implementation commit.

## Verifier plan

A fresh verifier should rebase the candidate onto the authoritative root and run the three focused groups once.
In the serialized signed-QA runtime, seed one planned estimated task and an active session, revoke deterministic Reminders permission, and confirm the exact retained counts and active-tracking copy.
Create a local task from the banner, restart app and helper, confirm the plan and session remain, then restore permission and confirm the banner disappears without losing local work.
The tracker, registry, runtime, and Lavish artifact remain untouched by this implementation lane.
