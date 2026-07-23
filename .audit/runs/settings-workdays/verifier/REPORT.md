# Settings working-day verifier report

## Verdict

Scenario `ZC-044-002` is fully implemented end to end.

The signed Settings flow exposed locale-derived Sunday-through-Saturday controls, saved Tuesday as the only working day through the agent-owned versioned policy boundary, restored it after both application and helper restart, and kept the final selected day disabled with an explicit accessibility explanation.

The running agent immediately replaced Monday's scheduled Daily Review with `daily-review:2026-07-14`, and the restarted Monday dashboard reported zero available planning minutes because Monday was no longer a working day.

## Revisions and automated evidence

- Authoritative base: `4ce4d08`.
- Rebased candidate: `d6b1e4f`.
- `SettingsPolicyDraftTests` passed 33 of 33 tests in the verifier's single focused run.
- The single release QA package passed application, helper, LaunchAgent, Mach-service, and signing validation.
- Static inspection confirmed multi-window grouping preservation, deliberate one-window normalization after weekday changes, independent and overlapping conflict behavior, and shared planning, review, and coaching consumption of the saved weekday set.

## Signed acceptance

- Installed app: `/private/tmp/zoid-666-settings-workdays-install/Zoid 666 QA E2E.app`.
- Isolated runtime: `/private/tmp/zoid-666-settings-workdays-qa`.
- Build identity: `zoid-coach-d6b1e4fcf60349e41993155a54645635d337d31c-clean`.
- Policy version 2 stored exactly `[3]`, the canonical Tuesday weekday value.
- The signed interface showed Tuesday selected and disabled while all six other weekdays were available and not selected.
- The signed interface displayed both Work starts and Work ends beside the weekday controls before and after restart.
- The agent's action ledger contained `daily-review:2026-07-14` immediately after save, without an application restart.
- After application and helper restart, Settings restored Tuesday-only and the Monday dashboard calculated zero configured work capacity.

The concurrent-policy behavior remains covered by the focused two-controller and resolver tests.
The capped signed run prioritized persistence, restart, final-day protection, and runtime consumption and did not stage a second live Settings client.
