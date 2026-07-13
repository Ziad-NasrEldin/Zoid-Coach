# Recommended Bounded Sprint Candidate Report

## Scope

This candidate implements `ZC-015-004` from recommendation calculation through the directly startable Today action.

It reuses the existing durable custom-sprint command path and does not modify task-execution storage, XPC implementation, Settings workday files, or authoritative audit files.

## End-user behavior

- A ready recommended task whose estimate fits the available window retains the normal Start action.
- A ready recommended task whose estimate exceeds the available window receives a bounded sprint suggestion.
- The suggested duration equals the available minutes up to a restrained 25-minute maximum.
- No sprint is suggested when zero minutes are available.
- The recommendation sentence names the task, available-time mismatch, sprint duration, and incomplete-at-expiry behavior.
- Today exposes one primary `START N-MINUTE SPRINT` button instead of competing generic and sprint actions.
- The button uses `today.recommendation.start-sprint` and a complete task-specific accessibility label and hint.
- The action is disabled while any task command is pending and routes through the existing serialized custom-sprint client.

## Compatibility

The new recommendation field is optional and legacy persisted snapshots decode with no suggested sprint.

Existing recommendation scoring and task selection remain unchanged.

Existing preset and custom sprint controls remain available on task surfaces.

## Verification

`swift test --filter TodayDashboardTests` passed 22 tests.

`swift test --filter "customSprintAcceptsBoundedDuration|agentBoundedSprintRemainsActive"` passed 2 tests.

The proof covers fit versus oversized recommendations, exact 20-minute suggestions, 25-minute capping, zero-availability suppression, truthful copy, legacy decoding, arbitrary bounded duration acceptance, expiry without completion, open-ended continuation, and restart recovery.

The full app and agent targets compiled as part of the focused Swift test build.

## Independent verifier plan

1. Integrate the candidate onto the authoritative root and build the signed QA app.
2. Seed a ready 90-minute task with exactly 20 minutes of current capacity.
3. Open Today and confirm one 20-minute sprint recommendation with the full task title and incomplete-at-expiry copy.
4. Inspect the button's accessibility label, hint, and stable identifier.
5. Click the sprint action once and confirm the task becomes the single active task with a 20-minute countdown.
6. Relaunch the app and helper and confirm the same sprint continues without resetting or duplicating tracked time.
7. Advance the signed fixture beyond the boundary and confirm the task remains active and incomplete with Continue Open-Ended available.
8. Seed the same task with 40 available minutes and confirm the suggested sprint is capped at 25 minutes.
9. Seed zero available minutes and confirm no sprint action is offered.
10. Seed a 15-minute task with 20 available minutes and confirm the normal Start action remains.
