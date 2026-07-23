# Learned Estimate Suggestions Candidate

## Scenarios

- `ZC-012-001` - See a suggested estimate based on similar completed tasks when enough history exists.
- `ZC-012-002` - See how many similar tasks support the suggestion.
- `ZC-012-003` - See the historical duration range behind the suggestion.
- `ZC-012-004` - Understand when the evidence is uncertain.
- `ZC-012-005` - Accept the suggested estimate.
- `ZC-012-006` - Keep the original estimate instead.
- `ZC-012-007` - Enter a different estimate.
- `ZC-012-008` - Avoid receiving a confident suggestion when tracking coverage or sample size is insufficient.
- `ZC-012-009` - Avoid having an advisory estimate silently replace the user's estimate.

## Implemented Behavior

The Today agent now reads the existing durable estimate-learning aggregate for each planned task using the same task-type and Reminder-list context used when completed-task evidence was recorded.

No suggestion appears before the learning policy's minimum eligible sample threshold is satisfied.

The agent resolves only the exact immutable sample identifiers included by the aggregate, derives the actual aligned-work minimum and maximum, and suppresses advice if evidence is missing or inconsistent.

The recommendation applies the learned robust ratio to the current task estimate, rounds to five minutes, and retains the existing policy bounds.

The current estimate remains unchanged in the snapshot until the user explicitly chooses Use.

Today shows the recommendation, exact supporting task count, historical aligned-duration range, and an Early Pattern or Established Pattern label.

The card explicitly says the advice is advisory and that no estimate changes until Use is selected.

Use follows the existing durable estimate-mutation path and then confirms that another estimate can still be chosen.

Keep leaves the original estimate or explicit Unknown choice untouched and shows direct confirmation.

The existing preset choices remain available, and the primary Today estimate strip now also exposes validated custom minutes with Save, Cancel, Return, and corrective error copy.

The suggestion is part of the cached Today snapshot and survives app or agent reconstruction without rewriting historical learning evidence.

## Focused Verification

The command `swift test --package-path /private/tmp/zoid-666-impl-next-e2e --filter LearnedEstimateSuggestionTests` passed.

Four focused tests prove three-sample suppression, four-sample appearance, exact recommendation and evidence range, limited-confidence copy, no silent overwrite, restart durability, established-confidence copy, explicit Use and Keep feedback, Unknown preservation, and optional snapshot coding.

`git diff --check` passed.

## Independent Verifier Plan

Rebase or integrate the candidate onto the latest authoritative root in an isolated verifier worktree.

Run `LearnedEstimateSuggestionTests` once and inspect the claimed source diff for threshold, context, and evidence-ID fidelity.

Build one clean signed QA package.

Seed an isolated canonical QA database with one 30-minute planned task and only three eligible matching completion samples, launch Today, and prove that no suggestion is shown.

Add the fourth eligible sample, regenerate the Today snapshot through the signed helper, and prove the card shows the exact recommendation, four-task count, aligned-duration range, Early Pattern label, and advisory copy while the task remains at 30 minutes.

Choose Keep and prove the task stays at 30 minutes with direct confirmation.

Relaunch, choose Use, and prove the durable plan changes to the recommendation only after that action.

Open Custom, verify malformed and out-of-range values remain unsaved with corrective copy, then save a different valid value and prove it persists after relaunch.

Repeat with insufficient tracking coverage and prove no confident suggestion appears.
