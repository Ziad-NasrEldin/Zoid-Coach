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

## Independent verifier result

Both focused Settings policy and gaming drift groups passed once on the candidate.
The verifier confirmed bounded controls, legacy Gentle and Accountability decoding, field-level conflict recovery, configured runtime enforcement, and intentional-override suppression taking precedence while active without bypassing the later daily cap.
The release artifact built successfully.
The single signed-QA package attempt passed signing, package verification, exact helper registration, and launch from `/private/tmp/zoid-666-coaching-limits-installed/Zoid 666 QA E2E.app`.
The installed Settings UI visibly changed the cap from 1 to 2 and cooldown from 180 to 35 minutes with the expected accessible values.
The stop instruction arrived before Save, relaunch, seeded sessions, or helper restart, so persistence and installed runtime enforcement remain unqualified.
