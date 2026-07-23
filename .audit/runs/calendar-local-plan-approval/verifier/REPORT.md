# Calendar Local Plan Approval Verifier Report

## Verdict

`ZC-046-009` is not independently verified as fully usable end to end.
The candidate implementation, focused state proof, release package, and signing checks passed.
The signed installed journey was deliberately deferred because the shared empty-window shell diagnosis is red.
The tracker status must remain unchanged until the shell fix permits installed proof.

## Candidate boundary

Candidate `7ab2b9f` was cherry-picked into an isolated branch created from authoritative tip `66e5098`.
The resulting candidate commit is `3a802d1`.
No implementation repair was required.

## Automated verification

The single focused invocation `swift test --filter CalendarPlanApprovalState` passed the selected suite with zero failures.
The focused proof covers unavailable preflight, local-only approval, exact task restoration, zero command identities, truthful receipt copy, no modal reopening after restore, and refusal to silently downgrade a Calendar-backed review.

## Release package

The one allowed release QA package completed successfully.
The release app completed in 70.0 seconds and the helper completed in 7.2 seconds.
Package identity, LaunchAgent identity, Mach service identity, and deep code-sign validation passed.
The prepared signed package is `/private/tmp/zoid-666-verify-calendar-local-plan/.build/app-qa/Zoid 666 QA.app`.

## Deferred installed acceptance

No app was installed and no LaunchAgent was registered in this verification run.
The root orchestrator directed conservative integration while the shared empty-window shell diagnosis remains red.
The signed journey must be repeated after the shell fix.

The deferred acceptance must prove:

- Calendar-unavailable preview uses configured work windows and exposes `USE PLAN LOCALLY`.
- The exact reviewed tasks persist in the local plan.
- The receipt reports zero Calendar and Reminder commands and an explicit local-only boundary.
- App and helper relaunch restore the plan and receipt without reopening the modal.
- A Calendar-backed review cannot silently downgrade to local-only approval.
- The Calendar repair and fresh review path remains available.

## Classification

The implementation has focused automated proof and a successful signed package boundary.
It does not have complete installed end-user proof.
`ZC-046-009` must not be promoted to fully implemented from this verification run.

