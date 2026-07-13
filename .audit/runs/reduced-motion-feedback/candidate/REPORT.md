# Reduced-motion state feedback candidate report

## Scope

This candidate implements `ZC-055-011` and `ZC-056-010` across the shared Sumi controls, Today planning, task estimates, usage details, and reminder-list reordering.

It does not touch Daily Review, notification delivery, prompt persistence, task mutation, root, runtime installation, tracker, registry, or Lavish.

## End-user behavior

When macOS Reduce Motion is enabled, pressed controls retain opacity and color feedback without shrinking.

Plan rows appear and disappear immediately without scaling.

Usage filters and rows update immediately without sliding from an edge.

Estimate confirmations update immediately without a scale or pop transition.

Reminder-list move and drop actions update immediately without an animated reorder.

Dropdowns and modal overlays appear immediately while retaining their complete labels, focus order, state copy, and actions.

Standard mode retains the existing restrained ease-out motion between 150 and 220 milliseconds.

## Implementation

`SumiMotionPolicy` is the single testable contract for whether state animation and spatial motion are allowed.

`SumiMotion` resolves optional animations, transitions, and pressed-state scale from that policy.

All 29 owned motion call sites now consume the environment-backed policy instead of mixing conditional animations with unconditional scale, offset, and reorder movement.

Reduced mode always sets `preservesImmediateFeedback` because the visible state, label, color, count, or selection changes synchronously even when motion is removed.

## Focused verification

- `swift test --filter SumiThemeTests` passed.
- The focused build compiled the complete app and both owned Today surfaces.
- Four Sumi theme and motion tests passed, including reduced and standard policy contracts.
- `git diff --check` passed.
- A static old-pattern audit found zero unconditional ease-out reorders, zero legacy reduced-motion animation ternaries, and zero direct scale, offset, or asymmetric transitions in the owned files.

## Parallel verifier plan

The verifier should rebase the candidate onto the newest authoritative root and rerun only `SumiThemeTests` plus any directly affected Today motion tests added after this candidate.

The verifier should launch one clean signed QA package without changing the user's system setting.

The verifier should inject `accessibilityReduceMotion = true` into focused view-host fixtures for a pressed Sumi action, a plan-row insertion, usage-mode change, estimate confirmation, and reminder-list reorder.

The verifier should confirm every state label, selection, count, focus target, and action remains present while no scale or offset motion is applied.

The verifier should repeat one representative in standard mode and confirm the restrained transition remains.

Only the verifier should update the tracker, registry, or Lavish after installed proof.
