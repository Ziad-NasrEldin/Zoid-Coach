# Menu bar coaching pause candidate report

## Candidate scope

- `ZC-023-004` now has a dedicated menu-bar state for a durably paused coaching policy.
- `ZC-023-009` now has direct pause and resume controls in the menu bar.
- This is implementation evidence only and does not promote either scenario in the authoritative tracker.

## End-user behavior

- The menu shows whether coaching is running or paused.
- Pausing explains that behavior prompts and automatic actions stop while task tracking and Today stay available.
- The pause button remains disabled while the current policy is loading or the mutation is saving.
- The menu shows progress, confirmed success, and durable-save failure states.
- The header adopts a distinct paused coaching icon and label without hiding the current task.
- Resume is available from the same menu-bar surface.
- Accessibility identifiers and explicit labels cover the control, pause action, resume action, progress, success, and error states.

## Persistence and safety

- The controller reloads the newest policy before each mutation.
- The controller changes only `automationPause` and preserves every unrelated policy field.
- The mutation is routed through the canonical background-agent XPC client.
- The menu does not claim success until it validates the accepted receipt, request ID, expected version, resulting version, payload digest, and mutation origin.
- A failed or unconfirmed mutation reloads the winning durable policy and keeps the UI truthful.

## Focused evidence

- `swift test --filter MenuBarCoachTests` passed 10 tests on 13 July 2026.
- The tests cover paused-state precedence, durable pause, durable resume, unrelated-policy preservation, version advancement, audited system origin, and invalid-receipt rejection.
- `swift build -c release --product ZoidCoach` completed successfully.
- The release build emitted only pre-existing warnings in `CodexJobCoordinator.swift` and `VoiceAudioEngine.swift`.
- `git diff --check` completed successfully.

## Independent verifier plan

1. Rebase or cherry-pick this candidate onto the current authoritative integration revision.
2. Build, sign, install, and launch a fresh QA application and helper from that exact revision.
3. Open the menu bar and confirm that the coaching control initially matches the durable policy.
4. Activate Pause and confirm the progress state, the confirmed paused state, the paused header icon, and the explanatory copy.
5. Confirm that Today still opens and task start, pause, break, resume, and tracked-time behavior remain usable while coaching is paused.
6. Produce eligible behavior evidence and confirm that behavior interventions and automatic actions remain suppressed while paused.
7. Close and reopen the menu, restart the app, and restart the helper to prove the paused state persists.
8. Resume from the menu and confirm that the durable policy version advances and eligible coaching can run again.
9. Change pause state from Settings while the menu is open, then use the menu control and confirm that the newest policy is reloaded without overwriting unrelated fields.
10. Exercise the control with keyboard navigation and inspect its accessibility labels and identifiers.

## Promotion boundary

- Keep `ZC-023-004` and `ZC-023-009` at their existing tracker statuses until the signed installed-app verifier completes the plan above.
- Signed runtime proof must include intervention suppression, restart persistence, continued Today usability, and successful resume.
