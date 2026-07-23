# Gaming Budget Transparency Candidate

## Claim

- Scenario IDs: `ZC-030-001`, `ZC-030-002`, `ZC-030-003`, `ZC-030-004`, and `ZC-030-005`.
- Production files: `Sources/ZoidCoachCore/TodayDashboard.swift`, `Sources/ZoidCoachApp/Views/DashboardView.swift`, and `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`.
- Test files: focused Today dashboard and gaming status tests only.
- Excluded: quiet-hours and notification delivery, policy mutation, accepted breaks, tracker, registry, backlog, Lavish, root, and runtime.

## Acceptance Target

Today explains base, earned, used, still locked, remaining, and same-day overage minutes separately, while a brief launcher transition shorter than two continuous minutes is observed but does not consume the meaningful gaming allowance.

Aligned-focus earning, daily earning caps, debt policy, carryover, and manual adjustments remain explicitly outside this batch.

## Implemented

- `GamingStatus` now separates base allowance, automatically earned reward, meaningfully used minutes, still-locked configured reward, remaining allowance, and same-day overage.
- Persisted legacy Today snapshots decode the new fields as zero, preserving restart compatibility.
- The behavior sessionizer counts gaming toward the allowance only after two continuous minutes, while preserving the underlying application observation breakdown.
- Separate launcher transitions never merge across work activity or telemetry gaps.
- Both Today presentations show the complete breakdown, the next unlock condition, and the meaningful-session rule without framing overage as punishment.

## Focused Proof

- `TodayDashboardTests` passed after the core and UI changes compiled.
- `briefGamingTransitionDoesNotConsumeAllowanceButMeaningfulSessionDoes` passed.
- `gamingStatusSeparatesBaseEarnedLockedRemainingAndSameDayOverage` passed.
- `git diff --check` passed.

## Verifier Plan

1. Rebase onto the latest authoritative branch and rerun the two new focused tests plus affected Today dashboard tests.
2. Seed a signed QA day with a one-minute launcher transition followed by a separate three-minute gaming session.
3. Verify Today counts only the three-minute session as used while retaining raw observed application evidence in Reviews.
4. Verify the expanded and compact Today surfaces show identical base, earned, used, locked, remaining, and overage values.
5. Complete the configured priority condition and prove earned replaces locked without losing used time across restart.
6. Verify a legacy saved Today snapshot restores with zero-valued new fields instead of failing decode.
7. Only after installed proof, update tracker, registry, backlog, and Lavish conservatively.
