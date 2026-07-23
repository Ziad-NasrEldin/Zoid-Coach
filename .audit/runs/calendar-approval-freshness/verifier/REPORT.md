# Calendar approval freshness independent verification

## Verdict

The candidate is accepted for controlled runtime verification.
No code blocker or corrective patch was found during independent inspection.
The implementation prevents a stale or unavailable Calendar approval from reaching the scheduling XPC boundary, preserves the reviewed plan on refusal, and exposes usable refresh and Source Health repair actions.

## Revision identity

- Authoritative base: `c51f860`
- Submitted candidate: `d9fa210`
- Candidate rebased by clean cherry-pick: `ace8c8e`
- Verifier branch: `codex/verify-calendar-approval-freshness`

## Static acceptance evidence

- The approval review captures a normalized availability revision containing sorted work intervals, visible Calendar identifiers, and relevant non-Zoid commitments intersecting work windows.
- Commitment identity covers identifier, start, end, and Calendar identifier, so mutation, cancellation, insertion, and calendar reassignment invalidate the reviewed revision.
- Confirmation refreshes planning capacity and runs freshness preflight before setting scheduling state or issuing the scheduling XPC request.
- Changed or unavailable Calendar state returns to review with an explicit nothing-written error.
- Refusal does not replace or clear the existing daily plan or its review items.
- The approval sheet provides `REVIEW UPDATED AVAILABILITY` and `OPEN SOURCE HEALTH` actions with stable accessibility identifiers.
- Reviewing updated availability creates a current review revision instead of silently accepting the stale review.
- Opening Source Health dismisses the approval sheet into the existing diagnostics repair surface.

## Focused verification

- `swift test --filter CalendarPlanApprovalStateTests` passed in its single permitted run.
- `swift test --filter QAFixtureOSCompositionTests` passed in its single permitted run.
- `swift test --filter PlanningCapacityStateTests` passed in its single permitted run.
- `ZOID_COACH_PACKAGE_MODE=qa CONFIGURATION=release ZOID_COACH_QA_RUN_ROOT="$PWD/.build/qa-calendar-approval-freshness" Scripts/package-app.sh` passed in its single permitted run.
- The packaged QA application is `.build/app-qa/Zoid 666 QA.app`.
- Release application and agent binaries built, package and LaunchAgent identities were coherent, Mach service validation passed, and code signing validation passed.

## Runtime lease boundary

No application install, launch, fixture mutation, shared runtime access, tracker edit, or Lavish edit was performed in this verifier lane.
The Daily Review highlights verifier owns the current runtime lease.
The following capped runbook is ready for the next exclusive QA runtime lease.

## Capped signed E2E commitment

1. Install the prepared signed QA package under a unique QA run root after orchestration grants the exclusive runtime lease.
2. Seed one realistic daily plan and one visible external Calendar commitment through the deterministic QA fixture controls.
3. Open Calendar plan approval and record the plan rows, capacity metrics, availability revision, scheduling command count, Calendar writes, Reminder writes, and persisted receipt state.
4. Mutate or cancel the external commitment after the approval sheet is open, then confirm the stale approval.
5. Require an explicit stale-availability refusal, zero new scheduling XPC commands, zero Calendar or Reminder writes, no applied receipt, and byte-equivalent preserved plan data.
6. Select `REVIEW UPDATED AVAILABILITY`, require refreshed capacity metrics and a current approval revision, and require the existing plan to remain intact.
7. Deny Calendar permission through the deterministic QA fixture, confirm again, and require an unavailable-source refusal, zero new scheduling commands or writes, and an unchanged plan.
8. Select `OPEN SOURCE HEALTH` and require the denied Calendar source, actionable permission guidance, and the existing repair control to be visible.
9. Restore Calendar permission, refresh the review, approve the current revision, and require exactly one successful scheduling command with the expected fixture writes.
10. Relaunch only after the successful approval and require the applied receipt and preserved plan to restore, while confirming neither refused attempt created a receipt.
11. Capture accessibility snapshots and fixture-state evidence for the mutation refusal, denied-source repair, successful write, and post-success relaunch states.
12. Stop after this single mutation branch, single denied-permission branch, single success branch, and single relaunch, then uninstall and clean only the unique QA run root.

The verifier signs this runbook as the remaining acceptance boundary for `ZC-008-017`, `ZC-009-007`, and `ZC-009-008`.
