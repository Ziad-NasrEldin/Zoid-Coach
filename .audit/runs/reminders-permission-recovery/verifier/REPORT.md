# Reminders Permission Recovery Verification

## Decision

All seven owned scenarios remain conservatively at `Touches remaining`, with the previously blocked no-repeat scenario now unblocked by signed QA and focused counter proof.

## Signed QA acceptance

The clean signed QA package installed with an isolated runtime root and its exact healthy LaunchAgent helper.
The fresh product visibly reached Reminders onboarding with a denied fixture, explained that no production Reminders access was attempted, and exposed Request Access, Not Now, Recheck, and Open System Settings.
After the explicit request, the signed product kept denied status, disabled Request Access, enabled Continue, and did not show another permission prompt.
Choosing Not Now visibly produced a local-only state that kept setup usable, named the unavailable Apple-task behavior, and kept one deliberate Request Access route enabled.
This verifier fixed the candidate's contradictory disabled state so a deferred user can actually use the promised explicit Request Access route later, while denied and granted users remain protected from repeated prompts.
The isolated fixture was then advanced to granted and the app was restarted.
The signed product returned to the exact Reminders step, displayed Healthy with deterministic QA evidence, disabled both Request Access and Not Now, and entered empty-list confirmation without touching production Reminders.

## Focused proof

- The complete RemindersConnectionController suite passed.
- Denied-to-healthy foreground inspection performs no second permission request.
- Deferred foreground checks remain local-only and prompt-free until the user explicitly requests access.
- Production System Settings success and failure injection paths expose truthful return or manual repair guidance.
- QA denied-to-granted-to-restart persistence uses only the isolated fixture boundary.

## Remaining boundary

The System Settings click was issued, but ScreenCaptureKit timed out before a stable native-settings capture and the subsequent foreground capture did not observe a scene-phase transition.
The deterministic foreground test and signed restart prove the recovery model, but the real EventKit denial and macOS settings mutation remain user-controlled, so no strict completion claim is made.

## Lineage

- Authoritative base: `b452949`.
- Rebased recovery implementation: `378614f`.
- Deferred explicit-request usability fix: `3723ce4`.
