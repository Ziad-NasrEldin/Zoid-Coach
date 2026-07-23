# Daily review behavioral highlights candidate

## Claim

- Primary scenario `ZC-041-009`: see the strongest observed work block for the selected day.
- Primary scenario `ZC-041-010`: see the largest observed drift episode for the selected day.
- Primary scenario `ZC-041-011`: see behavior coaching prompts and recorded responses for the selected day.

## Owned files

- `Sources/ZoidCoachCore/DailyReview.swift`
- `Sources/ZoidCoachInfrastructure/DailyReviewStore.swift`
- `Sources/ZoidCoachApp/Views/DailyReviewView.swift`
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift`
- `.audit/runs/daily-review-highlights/candidate/REPORT.md`

## Exclusions

- Calendar approval freshness files remain untouched.
- The root worktree, installed runtime, tracker, scenario registry, Lavish artifact, backlog, active-work ledger, and migration registry remain untouched.

## Planned acceptance

- The best work block is the longest corrected observed work session on the exact selected local day.
- The largest drift episode is the longest corrected gaming or distracting session on that day.
- Ties resolve deterministically to the earlier session.
- Each highlight shows classification, application, local time, duration, and an honest observed-evidence label.
- A day without an eligible work block or drift episode shows an explicit factual empty state.
- The review lists each gaming-drift or wake-intervention prompt created on the selected local day.
- Each prompt shows title, local time, recorded response and surface, or a clear no-response state.
- Applied response effects are distinguished from responses whose effect has not yet been applied.
- Corrections and recorded prompt responses remain visible after reopening the store and app.

## Evidence

- `DailyReviewSnapshot` now derives the longest corrected observed work session and the longest corrected gaming or distracting session.
- Duration ties resolve to the earlier session, giving stable output across reloads.
- The visible cards show duration, application, configured-local time, corrected classification, and an explicit observed-session label.
- Missing work or drift evidence renders `Not observed` with factual empty-state copy rather than a zero or inferred episode.
- `DailyReviewStore` reads only `GAMING_DRIFT` and `WAKE_INTERVENTION` prompts whose creation timestamps fall inside the exact configured local-day boundary.
- Planning, meeting, and onboarding prompts remain excluded from behavior coaching history.
- Each interaction preserves the prompt title and summary, creation time, response action, response surface, response time, and whether the durable response effect reached `applied`.
- The UI distinguishes no response, applied response, and recorded response with an effect still pending.
- The section states that the highlights are corrected local observations and not conclusions about why the activity happened.
- The focused restart journey corrects a five-minute YouTube gaming session to work, adds an equally long later Xcode work session, and proves the earlier corrected YouTube block wins the tie.
- The same journey proves the three-minute Steam session remains the largest drift episode after correction.
- It records an applied gaming-drift response, an unresolved wake intervention, and a planning prompt, then proves only the two behavior interactions appear with the correct response and applied states after reopening the store.
- `swift test --filter DailyReviewTests` passed with exit code 0.
- `swift test --filter dailyReviewShowsCorrectionAwareHighlightsAndBehaviorCoachingResponsesAcrossRestart` passed with exit code 0.
- `git diff --check` passed.

## Conservative status recommendation

- Keep `ZC-041-009` below fully implemented until a verifier sees the corrected longest-work result, deterministic tie, empty state, local time, and restart persistence in the signed app.
- Keep `ZC-041-010` below fully implemented until a verifier sees corrected gaming and distracting candidates, largest-episode selection, empty state, and restart persistence in the signed app.
- Keep `ZC-041-011` below fully implemented until a verifier sees applied, pending, and unanswered behavior prompts while confirming unrelated planning prompts remain absent.

## Independent verifier plan

- Rebase this candidate onto the latest authoritative integration commit before verification.
- Run `swift test --filter DailyReviewTests` from the rebased candidate.
- Package and install a clean signed QA identity without touching production data.
- Seed two equal-duration observed work sessions at different times and verify the earlier session is shown as the strongest work block.
- Correct a longer gaming session to work and verify both work and drift highlights recalculate immediately.
- Seed gaming and distracting sessions with distinct durations and verify the largest eligible corrected episode is shown.
- Inspect duration, application, configured-local time, classification, evidence label, layout, and accessibility at supported window sizes.
- Open a day with no work and no drift evidence and verify both explicit `Not observed` states.
- Seed one applied gaming-drift response, one response with a pending effect, one unanswered wake intervention, and one planning prompt.
- Verify the behavior coaching list shows the three behavior states with response action and surface while excluding the planning prompt.
- Relaunch the app and helper, then confirm highlights and coaching history remain identical.
- Update the tracker, registry, backlog, and Lavish artifact only from the authoritative root after signed proof passes.

## Known boundaries

- `Strongest work block` means the longest corrected observed work session, not a subjective productivity score.
- `Largest drift episode` means the longest corrected observed gaming or distracting session under the existing five-minute sessionization gap.
- This batch records intentional-continue responses as coaching history but does not calculate or claim the full override duration journey in `ZC-041-012`.
- Signed visual, accessibility, local-time-zone, correction, empty-state, response-state, filtering, and restart proof remains assigned to the independent verifier.
