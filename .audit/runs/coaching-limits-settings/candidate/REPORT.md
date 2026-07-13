# Coaching limits Settings candidate

## Outcome

The user can now configure the maximum daily gaming-coaching prompts and the cooldown between separate prompts instead of inheriting fixed values from the coaching-level label.

## End-to-end behavior

- Settings exposes a daily prompt cap from 1 through 10.
- Settings exposes a separate-session cooldown from 5 through 1,440 minutes in five-minute steps.
- Both controls have stable accessibility identifiers.
- Both values persist in Gaming Policy through the existing authenticated Settings mutation boundary.
- Independent concurrent changes merge safely.
- Overlapping changes preserve the winning values and the user's values for explicit reapply.
- Gaming drift enforcement consumes the saved cap and cooldown.
- Daily cap enforcement remains separate from intentional-override suppression.
- Legacy policies without either field preserve the prior behavior: Gentle decodes to one prompt and 180 minutes; Accountability decodes to three prompts and 60 minutes.

## Verification

- `swift test --filter SettingsPolicyDraftTests` passed.
- `swift test --filter GamingDriftPromptServiceTests` passed.
- The configured runtime fixture proves a 35-minute cooldown suppresses at 30 minutes, permits a second prompt at 36 minutes, and a daily cap of two suppresses the third eligible session.
- The exact legacy decode seam passed for Gentle and Accountability defaults.
- `git diff --check` passed.

## Acceptance boundary

The candidate does not claim installed Settings interaction or restart proof.
A fresh verifier should change both controls in signed QA, save through the helper, relaunch, exercise qualifying separate gaming sessions around the configured cooldown, and confirm the exact daily cap survives app and helper restart.
