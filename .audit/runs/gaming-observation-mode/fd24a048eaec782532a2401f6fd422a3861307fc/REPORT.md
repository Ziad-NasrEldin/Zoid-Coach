# Gaming observation mode verification

Candidate `fd24a048eaec782532a2401f6fd422a3861307fc` was independently rebased onto authoritative root `069022e` before verification.

## Result

ZC-029-001 is fully usable end to end in the installed signed QA application.

The user can disable the gaming budget and coaching prompts, save the policy through the running agent, relaunch the application, and retain observation mode.

The configured values remain visible and retained while their controls are disabled.

Today reports factual gaming minutes without presenting an allowance, unlock, debt, or behavior prompt.

## Focused proof

- `SettingsPolicyDraftTests` passed and covered policy round-trip plus disabled-value retention.
- `TodayDashboardTests` passed and covered factual observation-mode status without an invented budget.
- `gamingObservationModeNeverProducesABehaviorPrompt` passed after rebasing and covered prompt suppression at the producer boundary.
- The full `GamingDriftPromptServiceTests` group also exposed two existing parallel fixture collisions on the shared `(source_day, epoch)` primary key.
- Those collisions were outside the observation-mode test, and the affected observation-mode seam passed independently.
- The release build passed.
- One clean release-configured signed QA package and install passed with coherent app, helper, Mach-service, and signing identities.

## Installed end-to-end proof

- Settings initially showed a 60-minute base, 15-minute completion reward, 45-minute intentional override, one-prompt cap, and 180-minute cooldown.
- Disabling `Apply a gaming budget and coaching prompts` immediately exposed explicit observation-only copy and disabled all five numeric controls without clearing their values.
- Saving produced policy version 2 through the installed helper.
- App relaunch restored the toggle off and retained the exact 60, 15, 45, 1, and 180 values in disabled controls.
- The active policy row stored `budgetEnabled=false`, while the prior legacy row remained readable as `budgetEnabled=true`.
- A deterministic local seed produced one current Steam gaming session with exactly 42 factual minutes.
- After the helper restarted from PID 14378 to PID 25312 and the app relaunched, Today visibly showed `GAMING OBSERVED 42m`.
- Today visibly stated that observation mode applies no gaming budget, unlock, debt, or coaching prompt.
- The prompt inbox showed zero waiting decisions, and the durable `prompt_episodes` table remained at zero.

## Boundaries

The verification used the isolated QA root `/private/tmp/zoid-666-gaming-observation-qa` and did not touch production data.

No tracker status beyond ZC-029-001 is promoted by this run.
