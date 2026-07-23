# Dark appearance candidate

## Scope

This candidate owns `ZC-056-005`.
It removes the forced light appearance and makes the shared Sumi-Ink visual system follow the user's macOS appearance.

## End-user behavior

- Today, Reviews, Settings, onboarding, menu surfaces, sheets, controls, and status panels now resolve shared Sumi colors for Light or Dark appearance.
- The existing warm paper, ink, muted, red seal, positive status, wash, and rule relationships remain recognizable in both appearances.
- Text and control colors switch with macOS appearance without requiring an app-specific setting or restart.
- Dark surfaces use light ink and muted text, brighter status colors, dark paper and wash surfaces, and visible control boundaries.
- Light appearance retains the existing Sumi-Ink direction while strengthening low-contrast rule colors used around controls.

## Focused proof

- `swift test --filter SumiThemeTests` passed two focused tests.
- Both palettes meet at least 7:1 contrast for primary ink on paper, soft paper, and mist.
- Both palettes meet at least 4.5:1 contrast for muted text, accent controls, destructive text, and positive status colors on their intended surfaces.
- Both palettes meet at least 3:1 contrast for control boundaries against paper.
- Repository search confirms no `preferredColorScheme` override remains under `Sources/ZoidCoachApp`.
- `git diff --check` passed.
- Clean QA packaging passed the release app and agent builds, package identity validation, LaunchAgent and Mach-service validation, on-disk signature validation, and designated-requirement validation.
- The isolated artifact is `.build/app-qa/Zoid 666 QA.app`.

## Verifier handoff

A fresh verifier should rebase or cherry-pick this candidate onto the current integration tip and rerun the focused contrast tests plus a release build.
Using the serialized signed-QA runtime, launch with macOS in Light appearance and inspect Today, Reviews, Settings, onboarding, Background Agent, notification health, and the menu bar.
Switch macOS to Dark appearance while the app remains open and verify every visible surface updates without restarting or losing state.
Check normal, hover, pressed, selected, disabled, warning, destructive, success, text-field focus, toggle, dropdown, sheet, and empty-state presentations.
Verify task titles and status copy remain readable and that selected controls do not become dark text on a dark background or light text on a light background.
Switch back to Light appearance and verify the app updates immediately and retains the same navigation and task state.
The verifier owns visual screenshots, installed-app evidence, and any tracker, registry, or Lavish update.
The shared runtime and root worktree remain untouched by this candidate.
