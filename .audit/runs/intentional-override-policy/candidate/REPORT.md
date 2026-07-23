# Intentional Override Duration Policy Candidate

## Scope

This candidate implements `ZC-029-013`, and completes the configurable timing seam needed by `ZC-036-003` and `ZC-036-008`.

## End-user behavior

Gaming Allowance Settings now includes Continue Intentionally For with bounded five-minute steps from 5 through 1,440 minutes.
The value loads from the active policy, participates in field-level conflict resolution, saves through the existing authenticated policy mutation boundary, and reconstructs exactly after restart.
Existing policies decode to the prior 45-minute behavior without migration or silent change.

The gaming-drift producer now derives response-based suppression from the configured value instead of a hardcoded duration.
The durable Continue intentionally response remains the source of truth across app and helper restart.
Equivalent prompts stay suppressed inside the selected window, and eligible coaching can return after it expires.

## Safety

The control changes only prompt suppression duration.
It does not stop gaming accounting, erase used minutes, complete or hide priority work, alter the daily prompt cap, or bypass baseline, work-window, coverage, pause, and allowance gates.
Concurrent edits to the same duration preserve the winning value and retain the user's value for explicit reapply.

## Focused proof

- `swift test --filter SettingsPolicyDraftTests` passed.
- `swift test --filter GamingDriftPromptServiceTests` passed.
- Focused proof covers 25-minute round-trip, independent merge, overlapping reapply, restart-safe suppression at 20 minutes, and a new eligible prompt after 26 minutes.
- `git diff --check` passed.

## Verifier plan

Rebase onto the latest authoritative root and rerun the two focused groups once.
In serialized signed QA, set the duration to 25 minutes, save through the agent, relaunch Settings, create an eligible accountability prompt, choose Continue intentionally, verify suppression inside the window, advance beyond 25 minutes, and verify one new eligible prompt while gaming totals and incomplete priority work remain unchanged.
Keep tracker status conservative until that installed journey passes.
