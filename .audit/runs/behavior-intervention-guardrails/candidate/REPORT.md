# Behavior intervention guardrails candidate report

## Revisions

- Base: `db7db539c1e66a9bf983cf4e63d135a12b157f45`.
- Claim: `72b7ace`.
- Implementation: `8d6e820`.
- Candidate tip: this report commit.

## Implemented behavior

- Behavior intervention accounting remains scoped to same-day `GAMING_DRIFT` decision keys, so planning and source-warning prompts do not consume the behavior cap.
- A response to a gentle prompt suppresses new behavior interventions for exactly 15 minutes.
- A response to an accountability prompt suppresses new behavior interventions for exactly 20 minutes.
- Five-more-minutes and continue-intentionally responses retain their existing dedicated timing semantics.
- The five-minute follow-up offers `I am done today` while keeping the prompt within the maximum of three secondary actions.
- Selecting `I am done today` suppresses all later behavior prompts for the same local day, including after service reconstruction.

## Automated evidence

- `swift test --filter GamingDriftPromptServiceTests` passed after the final implementation.
- The focused suite covers unrelated prompt accounting, the exact 14-to-15-minute gentle boundary, the exact 19-to-20-minute accountability boundary, the end-day action, restart persistence, the existing configured cooldown, the existing daily limit, and intentional gaming overrides.
- `git diff --check` passed before commit.
- A release QA package completed successfully.
- The packaging verifier reported coherent app, LaunchAgent, Mach service, and signing identities.
- The packaged app was validated at `.build/app-qa/Zoid 666 QA.app`.

## Independent verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative root.
2. Install a freshly signed isolated QA build without replacing the normal installed app.
3. Seed a completed baseline, an incomplete priority task, and eligible capped gaming sessions.
4. Seed unrelated planning and source-warning prompts, then prove that they do not consume the behavior intervention cap.
5. Answer a gentle prompt, trigger another eligible gaming session at 14 minutes, and verify no prompt appears.
6. Repeat at 15 minutes and verify exactly one eligible prompt appears.
7. Answer an accountability prompt, repeat at 19 and 20 minutes, and verify the same closed-to-open boundary.
8. Choose five more minutes, wait for the follow-up, and verify that `I am done today` is visible and the prompt has no more than three secondary actions.
9. Select `I am done today`, restart the helper and app, trigger later gaming that same local day, and verify that no new behavior prompt appears.
10. Advance to the next local day and verify that normal behavior prompt eligibility returns.
11. Let the verifier alone update the scenario tracker, registry, and Lavish audit after recording runtime evidence.
