# Screenshot analysis consent candidate

## Scope

This candidate implements the consent and runtime enforcement foundation for `ZC-003-009` and `ZC-045-012`.
It does not change tracker status because installed UI and running-agent acceptance belong to a fresh verifier.

## User-visible behavior

- Fresh onboarding starts screenshot analysis off instead of silently inheriting the legacy enabled default.
- The Screenwatch step exposes `ALLOW SCREENSHOT ANALYSIS FOR AMBIGUOUS ACTIVITY` with a stable accessibility identifier.
- Off-state copy promises that screenshots are never inspected and ambiguous activity remains unknown for later review.
- On-state copy limits inspection to activity that app and time evidence cannot classify and states that the screenshot remains local.
- Continuing from Screenwatch persists the exact choice through the versioned policy mutation boundary before setup advances.
- A policy mutation failure leaves the user on the Screenwatch step with actionable failure copy.
- Existing users restore their persisted choice instead of being silently reset.
- Settings exposes the same ambiguous-only meaning and stable accessibility identifiers for the toggle and explanation.

## Runtime enforcement

- Screenshot analysis is deny-by-default when a caller omits authorization.
- Authorization requires explicit consent, material intervention value, a non-resource-constrained runtime, and a positive raw-screenshot retention window.
- The archive selects only records whose stored classification remains `unknown`.
- The archive rejects records older than the active retention boundary before image bytes reach the recognizer.
- Both continuous-agent and one-shot-agent paths now use the same active policy authorization.
- The prior one-shot path that analyzed screenshots without consulting policy is removed.
- Known Work, Gaming, Distracting, and Idle records remain untouched even when consent is on.

## Focused proof

- `swift test --filter screenshotAnalysis` passed the three new onboarding mutation tests and the archive eligibility test.
- The archive OCR persistence, duplicate suppression, QA evidence-cipher, meeting acceptance, and meeting edit seams passed with explicit authorization.
- The adjacent classification, schedule, durable receipt replay, and policy-before-progress onboarding tests passed.
- A clean QA release package at candidate `52462a4f9a46052270f8b1362f2b9c8ed66659e8` passed application and agent release builds, package identity checks, Mach-service checks, and strict code-signing validation.
- The broad onboarding filter was stopped after exceeding the bounded focused-test window without reporting a failure; no full-suite claim is made.

## Fresh verifier plan

1. Rebase the candidate once onto the current authoritative root and rerun only the screenshot-consent and affected meeting seams.
2. Install one signed isolated QA application under an exclusive runtime lease.
3. Reach Screenwatch onboarding and prove fresh default Off copy, stable control identity, and no screenshot-analysis policy mutation before confirmation.
4. Turn consent on, continue, and prove the next step appears only after the versioned policy stores `screenshotAnalysisEnabled = true`.
5. Relaunch and prove the persisted choice appears On in Settings with the same ambiguous-only explanation.
6. Seed one retained unknown screenshot, one retained known Work screenshot, and one expired unknown screenshot without using personal screenshot content.
7. Run the agent in a non-Observe mode and prove only the retained unknown screenshot receives an analysis row or structured evidence.
8. Turn consent off in Settings, save through the agent, relaunch the helper, seed another retained unknown fixture screenshot, and prove no new analysis row, OCR fact, or meeting candidate appears.
9. Inspect the QA database and prove screenshot pixels are absent while only permitted structured evidence and source metadata remain.
10. Capture the onboarding Off and On states, Settings restored state, allowed unknown result, and post-disable refusal before cleanup.

The verifier must keep tracker, registry, and Lavish status conservative until the complete installed journey passes.
