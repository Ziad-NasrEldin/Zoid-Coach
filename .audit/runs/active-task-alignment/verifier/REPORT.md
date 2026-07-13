# Active Task Alignment Verifier Report

## Verdict

`ZC-024-008` is not independently verified as fully usable end to end.
The candidate implementation, focused automated proof, release package, signed install, and helper startup passed.
The installed UI became unavailable during onboarding before the required Today journey could begin.
The tracker status must remain unchanged.

## Candidate and integration boundary

Candidate `ff774af` was cherry-picked into an isolated branch created from authoritative tip `7758ca6`.
The resulting candidate commit is `9f0fd47`.
The candidate already used the authoritative tip, so no rebase was required.

## Automated verification

The single focused invocation `swift test --filter "activeTaskTimeComparison|agentSnapshotShowsOnlyObservedAlignmentFromTheCurrentActiveSession"` passed all three selected Swift Testing cases with zero failures.
The proof covers elapsed versus observed-aligned separation, exclusion of pre-session observations, missing-evidence wording, neutral limitation copy, accessibility summary content, and the persistence-backed agent snapshot.
No implementation repair was required.

## Release and signed runtime

The one allowed release QA package completed successfully.
Package identity, LaunchAgent identity, Mach service identity, and deep code-sign validation passed.
The signed package installed at `/private/tmp/zoid-666-active-task-observed-install/Zoid 666 QA E2E.app` with isolated QA root `/private/tmp/zoid-666-active-task-observed-qa`.
The QA LaunchAgent registered and ran from the installed signed app.

## End-to-end acceptance blocker

The installed app initially rendered onboarding step 1 and exposed `onboarding.continue` through accessibility.
Pressing that accessibility control caused the Zoid window content tree to become empty.
The `ZoidCoachQA` process and its non-minimized 1180 by 760 window remained, but no Zoid UI was visible.
Reopening the installed app did not restore the window contents.

The verifier stopped after this current attempt as required by the runtime cap.
No source fixture was seeded after the UI failure.
The following required signed acceptance remains unverified:

- Start an active task with durable elapsed time.
- Show pre-session and current-session Screenwatch observations together.
- Prove Today displays Task elapsed separately from Observed aligned.
- Prove pre-session evidence is excluded.
- Prove missing and stale evidence states are labeled truthfully.
- Prove restart preserves the comparison.
- Prove visible and accessibility copy never claims alignment establishes task work.

## Classification

The implementation has focused automated proof and successful signed package/install boundaries.
It does not have complete installed end-user proof.
`ZC-024-008` must not be promoted to fully implemented from this verification run.

