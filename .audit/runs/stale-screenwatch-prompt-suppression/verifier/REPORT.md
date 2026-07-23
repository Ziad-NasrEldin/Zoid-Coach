# ZC-049-003 stale Screenwatch prompt suppression verifier report

## Result

`ZC-049-003` advances from Not implemented to Touches remaining.

The implementation now suppresses behavior coaching when Screenwatch evidence is missing, older than three minutes, or future-dated.

It also dismisses an unresolved gaming-drift prompt when a later evaluation finds Screenwatch coverage limited or stale.

The scenario is not Fully implemented because the signed runtime did not prove stale-to-fresh automatic recovery and prompt presentation end to end.

## Independent fixes

- A future-dated observation is no longer treated as fresh.
- A queued unresolved `GAMING_DRIFT` prompt is dismissed when Screenwatch later becomes missing, stale, or limited.
- The recovery test now uses one persisted service and one database across missing, stale, fresh, and stale-again transitions.
- Exact 180-second acceptance and 181-second rejection boundaries are covered.

## Automated proof

The following four focused tests passed together after the verifier fixes:

- `gamingDriftSuppressesPromptsWhenScreenwatchBecomesStaleAndRecoversWithFreshEvidence`
- `gamingDriftHonorsBasicPolicyAndCoverageGates`
- `gamingDriftHonorsPauseWorkWindowBreakEndDayAndIncompleteWorkGates`
- `gamingDriftUsesCorrectionsAndDoesNotRepeatTheSameSession`

The first test proves missing evidence suppresses with zero unresolved prompts, evidence older than three minutes suppresses, fresh evidence restores eligibility and queues exactly one prompt, and a later stale evaluation dismisses that unresolved prompt.

It also proves the exact freshness boundary and rejects future timestamps.

## Signed runtime proof

One QA release package completed successfully from verifier commit `51ae702085ec784000bd95c0f5621b2adb2fd511`.

The signed app and signed helper were installed and launched from an isolated QA runtime.

With Screenwatch deliberately missing, the native accessibility probe confirmed Today visible in a non-minimized 1180 by 760 window with 112 accessibility nodes.

The persisted `prompt_episodes` table contained zero rows.

After a signed app relaunch, Today remained visible with 111 accessibility nodes, and both total and unresolved prompt counts remained zero.

## Remaining proof gap

The isolated signed runtime began with zero baseline days, zero behavior records, and zero daily-plan entries.

The production eligibility path requires seven complete baseline days, a current main-objective plan, and an active work window before it can create a gaming-drift prompt.

Directly fabricating those production records would not be credible end-to-end proof.

A later signed run must establish those prerequisites through a supported fixture or real product journey, then prove stale suppression, fresh automatic recovery, one visible prompt, stale-again dismissal, and relaunch safety.
