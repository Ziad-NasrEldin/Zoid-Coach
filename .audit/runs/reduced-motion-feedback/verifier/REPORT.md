# Reduced Motion Feedback Verification

## Result

The reduced-motion candidate is accepted after one verifier fix.

The verifier found that this macOS SDK exposes `accessibilityReduceMotion` as a read-only environment value, so the candidate's policy-only tests could not provide the requested view-host proof.

The fix adds `SumiReduceMotion`, which defaults to the real macOS accessibility value and permits an explicit environment override only when a host needs deterministic verification.

All 16 owned environment consumers now use the same effective value.

## Scenario Scope

- `ZC-055-011` - Use the app with Reduce Motion enabled.
- `ZC-056-010` - Receive useful state feedback without relying on motion.

## Owned-Site Inspection

The three owned source files contain 32 `SumiMotion` helper calls across the candidate's 29 state-change sites.

The shared Sumi action and press styles remove pressed scaling in reduced mode while preserving opacity, border, fill, hover, label, and activation feedback.

Selectors and dropdowns update their fill, border, expanded state, complete menu content, and focus order immediately in reduced mode.

The shared modal overlay uses an identity transition in reduced mode while preserving the complete modal content and accessibility containment.

Reminder-list move-up, move-down, intermediate drop, and end-drop operations still execute the same model mutation with a nil animation transaction in reduced mode.

Daily-plan insertion and main-objective changes use identity transitions and nil animations in reduced mode while retaining every task row, label, action, and selected objective.

Time-slot pressed feedback retains its border and selection state without scaling.

Estimate selection and confirmation retain the selected duration, confirmation label, change action, custom entry, and accessibility label without scale or pop motion.

The Today usage control retains focus, keyboard behavior, selected category, selected presentation mode, usage labels, and rows without edge offsets.

Today plan-row state changes retain completion, recommendation, blocked-state, and estimate feedback without animated movement.

Standard mode continues to use the candidate's restrained 150 to 220 millisecond ease-out motion and spatial transitions.

No direct unconditional ease-out reorder, legacy reduced-motion ternary, pressed scale, offset transition, or asymmetric transition remains in the owned sites.

## View-Host Acceptance

`SumiThemeTests` passed once after the verifier fix.

Six focused tests passed.

The reduced-motion `NSHostingView` fixture injected the effective accessibility value and exercised a pressed action, plan-row insertion, usage-category switch, estimate confirmation, and reminder-list reorder.

Each interaction asserted that spatial motion was disabled, state animation was disabled, immediate feedback remained enabled, and the final user-visible label, row, duration, count, or order was preserved.

The standard-mode host proved a representative pressed action retained its 0.98 scale, 0.82 pressed opacity, pressed label, enabled motion policy, and immediate feedback.

## Release Package

The verifier ran the release QA package exactly once at commit `5d70aae`.

The command was `CONFIGURATION=release ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT=/private/tmp/zoid-666-reduced-motion-qa Scripts/package-app.sh`.

Both release products built successfully.

The package, embedded LaunchAgent, Mach service, signing identities, nested executables, and designated requirements passed verification.

The resulting package is `/private/tmp/zoid-666-verify-reduced-motion/.build/app-qa/Zoid 666 QA.app`.

After the prior verifier released the runtime lease, the verifier launched this exact signed package directly without installing a helper or changing the user's macOS Reduce Motion setting.

The live accessibility tree exposed the Zoid 666 window, complete onboarding content, progress state, Exit For Now action, Continue action, menu bar, and stable accessibility identifiers.

The package was then terminated and its disposable QA root was removed.

## Acceptance Boundary

The candidate and verifier changes do not alter task mutation, persistence, prompt delivery, notification behavior, runtime installation, the scenario tracker, the scenario registry, or Lavish artifacts.

The deterministic accessibility-environment host proof, standard-mode control, and live signed-package accessibility inspection jointly satisfy the two presentation-policy scenarios without mutating the user's system setting.
