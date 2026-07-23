# Prompt Task Block Candidate Report

Scenarios: `ZC-034-011`, with shared end-user coverage for `ZC-015-009` and `ZC-018-009`.

Candidate status: implementation complete and ready for independent signed runtime verification.

## End-User Journey Implemented

- Gaming-drift coaching prompts now offer a clearly named Mark blocked action for the unfinished task.
- Choosing Mark blocked opens a dedicated reason sheet without resolving the coaching decision.
- The sheet identifies the task, explains how blocking affects active work and today's objective, and supports cancellation.
- The reason is trimmed and must contain between 3 and 240 characters.
- Confirming sends the existing durable block mutation through the agent, pauses active work, saves the reason with the plan task, and selects a replacement main objective when available.
- The coaching decision resolves only after the block mutation is accepted.
- If validation or the agent mutation fails, the prompt remains open and the user receives truthful recovery copy.
- If prompt resolution fails after the block mutation succeeds, the blocked state remains saved and the prompt remains available for safe reconciliation.
- Prompt action controls now use an adaptive grid so the complete coaching choice set remains usable without horizontal clipping.
- Stable accessibility identifiers cover the sheet, reason editor, validation error, and confirmation action.

## Focused Proof

- `swift test --filter PromptTaskBlockStateTests` passed on 13 July 2026.
- `swift test --filter GamingDriftPromptServiceTests` passed on 13 July 2026.
- `swift test --filter TodayDashboardAgentTests` passed on 13 July 2026.
- The debug test build compiled the changed app, infrastructure, and test targets.
- `swift build -c release` passed on 13 July 2026.

## Independent Verifier Plan

1. Start the current main-objective task and produce a gaming-drift prompt in the signed QA app.
2. Verify the prompt names the task, shows Mark blocked without clipping, and exposes every other coaching action.
3. Open the blocker sheet, enter fewer than 3 characters, and verify the prompt remains unresolved with validation guidance.
4. Cancel once and verify the task remains active and the prompt remains open.
5. Reopen the sheet, enter a meaningful blocker, and save it.
6. Verify active work pauses, the exact reason appears on the blocked task, and a usable replacement becomes the main objective when available.
7. Verify the coaching decision moves to answered exactly once.
8. Relaunch and verify the blocked reason, revised objective, paused execution, and answered decision remain durable.
9. Repeat with the agent unavailable and verify the task remains unchanged while the prompt stays open with recovery guidance.

The tracker and registry should not promote these scenarios until the signed success, relaunch, and unavailable-agent journeys pass.
