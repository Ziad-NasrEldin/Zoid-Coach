# Gaming observation mode candidate

## Scope

- `ZC-029-001` - Observe gaming without applying a budget.

## End-user result

Settings now offers an explicit `Apply a gaming budget and coaching prompts` toggle.
When disabled, allowance, unlock, intentional-override, prompt-cap, and cooldown controls become inactive without discarding their configured values.
Settings explains that observation-only mode records factual gaming minutes and applies no allowance, unlock, debt, or behavior prompt.
Today changes `Gaming Budget` to `Gaming Observation`, shows exact observed minutes, and removes misleading remaining-budget language on both task surfaces.
Runtime status preserves factual used minutes with zero invented budget or unlock.
Gaming drift production stops with an explicit `gamingBudgetDisabled` reason and creates no prompt.
Legacy saved policies without the new field remain budget-enabled.

## Evidence

- Candidate implementation: `32ba2db`.
- `swift test --filter SettingsPolicyDraftTests` passed persisted toggle values, retained allowance settings, legacy behavior, and field-level conflict recovery.
- `swift test --filter TodayDashboardTests` passed factual used-minutes status with no budget or unlock claim.
- `swift test --filter GamingDriftPromptServiceTests` passed explicit observation-mode suppression plus existing baseline, override, break, cooldown, cap, and restart boundaries.
- `git diff --check` passed before the implementation commit.

## Verifier plan

A fresh verifier should rebase onto the authoritative root and run the three focused groups once.
In signed QA, disable the budget, save and relaunch, confirm all allowance controls remain disabled while their values persist, seed gaming evidence, verify exact observed minutes and no budget copy, restart the helper, and confirm no gaming prompt is created.
The root, runtime, tracker, registry, and Lavish artifact remain untouched by this implementation lane.
