# Daily Source Coverage Candidate Evidence

## Scope

This batch implements the end-user daily source coverage flow for ZC-024-005, ZC-024-009, ZC-024-010, ZC-041-003, ZC-041-004, ZC-041-006, ZC-041-007, ZC-041-008, ZC-041-014, and ZC-049-005.
The batch remains isolated from the authoritative tracker, registry, Lavish artifact, root branch, release build, and installed runtime.

## End-to-end behavior

The Daily Review now contains a dedicated Source Coverage card for the selected local day.
The card derives active-task, observed-task, aligned-work, missing-task, work, gaming, distraction, unknown, and idle minutes from the canonical local database.
Missing active-task time remains separate and is never relabeled as work, gaming, or distraction.
Unknown observations remain separate from distraction.
Idle totals are marked unreliable unless coverage is adequate and the newest Screenwatch checkpoint is healthy.
Exact-looking totals are limited to healthy, high-coverage tracked windows and never imply whole-day completeness.
Low coverage, missing checkpoints, stale checkpoints, and unreadable evidence produce visible user-facing explanations.
Daily review corrections alter derived review categories without rewriting the original behavior records.
The newest Screenwatch checkpoint persists in SQLite and explains incomplete coverage after the store is reopened.
Changing the selected day while a previous load is running cannot overwrite the newer day with stale results.
The user can retry a failed load and manually refresh the currently selected day.

## Recovery and privacy

The store opens the canonical database read-only and does not mutate evidence during review.
Database failures produce an unavailable state and do not infer missing time.
The source explanation displays only the existing checkpoint state, detail, evidence, and check time.
No screenshot contents, window titles, URLs, or raw observation payloads are surfaced by this view.

## Focused verification

`swift test --filter DailySourceCoverage` passed seven Swift Testing scenarios on 2026-07-13.
The focused tests cover complete tracked windows, incomplete coverage, absence of active tasks, idle reliability, absent source checkpoints, correction overlays, and checkpoint persistence after reopening.
`swift build --target ZoidCoachApp` passed on 2026-07-13.
`git diff --check` passed on 2026-07-13.

## Remaining acceptance boundary

This candidate still requires independent verification after rebasing onto the final authoritative integration tip.
The tracker statuses must not change until that verification confirms the built app and interactive Daily Review flow.
