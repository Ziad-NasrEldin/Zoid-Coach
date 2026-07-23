# Menu bar prompt fallback candidate report

## Revisions

- Base: `c6954d2`.
- Claim: `24feeb5`.
- Implementation: `77cac5f`.
- Candidate tip: this report commit.

## Implemented behavior

- The macOS menu bar uses an `exclamationmark.bubble.fill` badge when Notifications are unavailable and one or more unresolved decisions are waiting.
- The badge accessibility label states the exact unresolved-decision count.
- Opening the menu shows direct, non-alarmist fallback copy and a button that opens Today to the waiting decisions.
- The fallback is not shown merely because Notifications are unavailable when no decision is waiting.
- The fallback is not shown for unresolved decisions while notification delivery remains healthy.
- Existing start, pause, resume, break, end-workday, source-health, and Settings controls remain available in the same menu.

## Automated evidence

- `swift test --filter MenuBarCoachTests` passed after the final implementation.
- The focused state proof covers two waiting decisions with unavailable Notifications, the exact menu-bar badge and accessibility label, direct fallback copy, preservation of active-task controls, healthy-delivery suppression, and zero-decision suppression.
- The complete app target compiled as part of the focused Swift test run.
- `git diff --check` passed before commit.
- A release QA package completed successfully.
- The package verifier reported coherent app, LaunchAgent, Mach service, and signing identities.
- The signed candidate is available at `.build/app-qa/Zoid 666 QA.app`.

## Independent verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative root.
2. Install the freshly signed isolated QA app without replacing the normal installed app.
3. Run the QA fixture with Notifications denied and no unresolved prompts, then verify that no decision badge is shown.
4. Seed one unresolved prompt through the agent and verify that the menu-bar symbol changes to the decision badge without restarting the app.
5. Inspect the accessibility label and verify that it says one decision is waiting in Today.
6. Open the menu, verify the denial explanation, and use `OPEN DECISION IN TODAY` to reach the same unresolved prompt.
7. Return to the menu and exercise start, pause, resume, break, and end-workday controls while Notifications remain denied.
8. Seed a second unresolved prompt and verify that the visible and accessibility copy use the exact plural count.
9. Resolve both prompts from Today and verify that the badge clears after refresh without restarting.
10. Leave one prompt unresolved, restore notification permission, and verify that the fallback badge clears because normal delivery is available.
11. Restart the app and helper in the denied-plus-unresolved state and verify that the badge, count, Today navigation, and task controls recover from durable state.
12. Let the verifier alone update the tracker, registry, backlog, and Lavish audit after installed proof passes.
