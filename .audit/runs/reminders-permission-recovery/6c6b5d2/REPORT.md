+# Reminders permission recovery candidate

## Scope

This candidate owns `ZC-002-002` through `ZC-002-008`.
It completes the in-app grant, denial, deferred, repair, foreground recovery, and local-only continuity foundation without using the shared installed-runtime lease.

## End-user behavior

- Before the macOS prompt, onboarding explains exactly what full access enables and that setup remains usable with local tasks.
- Denied access now states that Apple tasks cannot enter Today or sync completion while local tasks and setup remain available.
- Deferring access persists an explicit local-only state and explains that Zoid 666 will not show the permission dialog again by itself.
- Request Access is disabled after a decision, so foreground checks and repeated refreshes use inspection only and never repeat the macOS prompt.
- Open System Settings reports whether the handoff succeeded and gives a manual Privacy & Security path if macOS cannot open it.
- Returning to the app automatically rechecks Reminders access in both onboarding and Settings.
- A repaired grant immediately loads Reminder lists in onboarding or incomplete tasks in Settings.
- The last successful Settings sync persists across controller reconstruction.
- Today local-task creation remains available independently of Reminders access.

## Focused proof

- `RemindersConnectionControllerTests` passed with denied, repair, automatic foreground recheck, failed Settings handoff, QA fixture, and reconstruction coverage.
- `returningFromSystemSettingsRepairsDeniedRemindersWithoutASecondPrompt` passed.
- `deferredRemindersRemainDeferredAcrossForegroundChecksWithoutPrompting` passed.
- The deterministic QA journey starts denied, opens the repair path once, changes the fixture to granted, returns to the app, reads one task, reconstructs the controller, and reads the same task again.
- The focused build compiled the app and test targets.
- `git diff --check` passed.

## Verifier handoff

A fresh verifier should rebase this candidate on the current integration tip, rerun the focused tests, then use the serialized signed-QA runtime to exercise denied, local-only continuation, Settings repair failure copy, granted return, list loading, task refresh, and restart.
The tracker, registry, and Lavish report remain root-owned and unchanged.

