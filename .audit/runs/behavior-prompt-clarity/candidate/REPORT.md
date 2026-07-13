# Behavior prompt clarity candidate report

## Candidate identity

- Base commit: `4e3a703`.
- Claim commit: `42b1f045274e0b486550b494247372f4b45d67a1`.
- Implementation commit: `008a4e0`.
- Scenarios: `ZC-033-006`, `ZC-033-007`, `ZC-033-008`, `ZC-033-009`, and `ZC-033-010`.

## End-user behavior implemented

- Every prompt is rejected before persistence when it offers more than three secondary actions.
- Contracted behavior prompts are rejected before persistence when their elapsed-minute statement does not match the source evidence interval.
- The gaming-drift prompt now states the exact observed minutes on both the initial intervention and the five-minute follow-up.
- The gaming-drift prompt explicitly says that observed activity does not establish why it happened or what the user intended.
- Contracted behavior prompts are rejected before persistence when they contain known guilt, insult, disappointment, moral-label, exaggerated-failure, or asserted-intent phrases.
- Existing non-behavior prompts remain compatible because the stricter copy and evidence checks are gated by an explicit behavior-prompt contract version.

## Automated proof

- Focused command: `swift test --filter "gamingDriftStaysQuietUntilBaselineCompletesThenQueuesEvidenceFirstPrompt|promptInboxRejectsMoreThanThreeSecondaryActionsOnEverySurface|behaviorPromptContractRejectsUnreliableCoerciveOrIntentAssertingCopy"`.
- Result: exit code 0.
- The focused tests prove valid gaming-drift prompt generation, a maximum of three secondary actions, exact elapsed evidence, an explicit uncertainty boundary, and rejection of invalid drafts without persistence.
- Release QA package command: `CONFIGURATION=release ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$PWD/.build/qa-behavior-prompt-clarity" Scripts/package-app.sh`.
- Result: exit code 0.
- The package check produced `Zoid 666 QA.app` and passed package, LaunchAgent, Mach service, and signing coherence validation.

## Fresh verifier plan

- Rebase or cherry-pick the candidate onto the current authoritative integration tip before testing.
- Build a fresh signed QA app from the rebased clean commit.
- Seed a completed baseline, a certain ten-minute Steam session, and an incomplete task named `Ship client proposal`.
- Confirm the Today prompt and its notification-facing representation show the same exact observed minutes and readable task title.
- Confirm the copy distinguishes observed activity from inferred reasons or intent.
- Confirm the prompt has one primary action and no more than three secondary actions.
- Submit crafted prompt drafts with four secondary actions, mismatched elapsed evidence, coercive language, asserted intent, and no uncertainty boundary.
- Confirm every invalid draft is rejected and none appears after reopening the persistent inbox.
- Exercise limited source coverage and confirm the gaming intervention stays suppressed while the Today source-health state explains the uncertainty.
- Restart the QA app and confirm the same valid unresolved prompt remains usable without duplicate persistence.
- Update the tracker, registry, and Lavish audit only from the verifier lane after fresh end-to-end acceptance.

## Integration boundary

This candidate does not modify the authoritative root, installed runtime, tracker, registry, backlog, or Lavish artifact.
The authoritative root advanced after this lane began, so a fresh verifier must resolve integration against that newer tip.
