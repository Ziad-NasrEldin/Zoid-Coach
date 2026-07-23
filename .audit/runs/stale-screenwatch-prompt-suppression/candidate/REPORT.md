# Stale Screenwatch Prompt Suppression Candidate

## Scope

This candidate implements `ZC-049-003` without changing the tracker, registry, Lavish audit, runtime fixtures, or shared application surfaces.

## User behavior

- Behavior coaching requires a Screenwatch observation no older than three minutes before evaluating gaming drift.
- Missing or stale Screenwatch evidence returns the existing limited-coverage suppression state before any prompt can be queued.
- Stale evidence creates no unresolved dashboard or notification decision and dismisses any unresolved gaming-drift prompt that became stale after it was queued.
- Fresh Screenwatch evidence restores prompt eligibility automatically in the same persisted service, and repeated evaluation stays exactly once.
- Existing policy, baseline, pause, work-window, accepted-break, end-workday, correction, and exactly-once prompt gates remain intact.

## Verification

- `gamingDriftSuppressesPromptsWhenScreenwatchBecomesStaleAndRecoversWithFreshEvidence` passed.
- `gamingDriftHonorsBasicPolicyAndCoverageGates` passed.
- `gamingDriftHonorsPauseWorkWindowBreakEndDayAndIncompleteWorkGates` passed.
- `gamingDriftUsesCorrectionsAndDoesNotRepeatTheSameSession` passed.
- `swift build -c release` passed.

## Verifier handoff

Independent verification should seed an eligible gaming drift session, advance Screenwatch beyond the three-minute freshness boundary, and prove no behavior prompt appears in Today or notifications.

After a new fresh gaming observation, the same signed runtime should prove coaching eligibility returns without restart while every normal policy gate remains effective.
