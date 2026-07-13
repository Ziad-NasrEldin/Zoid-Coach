# Recovery follow-through review candidate

## Scope

This candidate covers `ZC-059-004`, `ZC-059-009`, `ZC-059-010`, and `ZC-060-008` without changing authoritative scenario status.
The daily review decodes the durable gaming intervention payload into separate observed application, observed gaming minutes, and unfinished task evidence.
Applied return-to-task and sprint choices create a recovery start.
A recovery is counted as an observed return only when correction-aware work evidence exists within 30 minutes of the response.
Task-specific return is claimed only when that later corrected work is attached to the selected task.
If no later work is visible, the review says the recovery started and follow-through was not observed.
Accepted breaks, five-minute extensions, pending effects, unanswered prompts, and intentional choices remain distinct outcomes.
Intentional gaming is labeled as a recorded choice with no judgment.

## User-facing result

Behavior Coaching now shows observed-return, recovery-start, and intentional-choice totals.
Each intervention shows its original factual summary, structured gaming and unfinished-task evidence, the derived outcome, and the exact response surface.
Stable accessibility identifiers cover the summary ledger, evidence row, and outcome row.

## Focused verification

- `swift test --filter DailyReviewTests` passed after the implementation and again after the selected-task follow-through fixture was added.
- The restart fixture proves structured gaming evidence, an intentional choice, an unanswered intervention, an applied 20-minute recovery with corrected selected-task work, and an applied return with no observed follow-through.
- `git diff --check` passed.

## Independent verifier plan

1. Integrate the candidate onto the current authoritative root and build a signed QA package.
2. Seed one gaming-drift episode that names observed minutes, application, and unfinished task.
3. Respond with the 20-minute work sprint and create corrected work attached to the selected task within 30 minutes.
4. Open the current-day review and prove the structured evidence, recovery-start count, observed-return count, selected-task outcome, response action, and response surface.
5. Seed an applied recovery response without later work and prove the review says follow-through was not observed instead of claiming success.
6. Seed Continue intentionally and prove the review records the choice without judgment and does not count it as recovery.
7. Relaunch the app and prove the same evidence and counts restore from durable local data.
8. Confirm the review and relaunch again to prove confirmation does not erase or rewrite intervention history.
