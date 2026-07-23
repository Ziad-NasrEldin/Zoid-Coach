+# Behavior coaching verification

## Scope

This batch adds the first production gaming-drift prompt producer and the configurable coaching-level foundation for scenarios `ZC-031-001` through `ZC-031-010`, `ZC-032-001`, `ZC-032-004`, `ZC-032-005`, and `ZC-033-001` through `ZC-033-005`.

## Implemented behavior

- The agent evaluates a fresh, correction-aware continuous gaming session after ten observed minutes.
- It stays quiet during the seven-complete-day baseline, Observe mode, automation pause, accepted breaks, workday closure, times outside the work window, limited telemetry, unlocked gaming allowance, and days without incomplete priority work.
- One decision key identifies each continuous gaming session across unresolved, resolved, expired, and restarted state.
- Gentle coaching permits one daily prompt.
- Accountability coaching permits at most three daily prompts with a sixty-minute cooldown between separate sessions.
- Settings exposes the coaching level and persists it through the versioned policy store with concurrent-edit recovery.
- The prompt leads with the observed minutes and application, names the unfinished priority task, avoids intent claims, and gives Return to task one primary role.
- Notification and Today surfaces share the same durable prompt episode and the same bounded action set.
- Return to task starts the named task through the canonical execution store exactly once.

## Verification

- Focused gaming prompt, notification mapping, response routing, Settings round-trip, and policy-conflict tests passed.
- The verifier added explicit proof that a resolved prompt still deduplicates the same session and enforces cooldown after reopening both the prompt store and coaching service.
- The verifier fixed the exhaustive QA notification-action matrix for the new gaming category.
- The full Swift suite passed with 593 tests in seven suites.
- The release build passed.
- A signed QA package passed package, LaunchAgent, Mach-service, and signing-identity verification.
- The installed signed QA agent remained silent with six complete baseline days, ten fresh gaming observations, an incomplete priority task, and granted fixture notifications.
- The signed package persisted the agent heartbeat while the baseline-suppressed state produced zero gaming prompts and zero notifications.

## Conservative runtime boundary

The installed post-baseline active-prompt leg was not completed in this pass.
The acceptance fixture changed the historical `policy_versions` payload but not the canonical `settings.value_json` pointer used by `PolicyStore`, so the signed runtime correctly continued using the default daytime window and sixty-minute allowance.
A read-only diagnostic confirmed current telemetry and seven complete baseline days, then reported `outsideWorkWindow` under that unchanged canonical policy.
The deterministic integration suite still proves active prompt creation, Today persistence, notification action bounds, primary return action, same-session dedupe, cooldown, daily cap, resolved-key persistence, and restart recovery.
All affected tracker rows therefore remain unchecked as `Touches remaining` until a later signed installed run saves the acceptance policy through the canonical policy-mutation surface and visibly completes the active notification and Today response leg.

