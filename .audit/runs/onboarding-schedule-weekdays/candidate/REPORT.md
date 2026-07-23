# Onboarding schedule weekdays candidate report

## Scope

- `ZC-005-007` - Configure a flexible work window.
- `ZC-005-008` - Configure quiet hours.

## End-user behavior

- The onboarding Schedule step now exposes all seven workday choices instead of silently retaining a fixed default weekday set.
- Each weekday button reports a stable accessibility identifier, human weekday label, and selected state.
- At least one workday is required before Continue becomes available.
- The exact selected weekdays, work start and end, and quiet start and end are persisted in the same policy mutation.
- The confirmation copy states how many workdays are selected, whether each window is same-day or overnight, and which local timezone is being used.
- Existing non-quarter-hour values remain available through the existing exact-minute picker behavior.

## Focused proof

- `swift test --skip-build --filter classificationAndScheduleAreAppliedBeforeAdvancing` passed after a successful focused compile and proves Monday plus Saturday, 08:30-17:15, and 21:45-06:30 persist together.
- `swift test --skip-build --filter onboardingScheduleRejectsEmptyWindowsAndAcceptsOvernightWorkAndQuietHours` passed and proves empty weekday selection blocks Continue, one weekday restores eligibility, and overnight quiet-hour copy is explicit.
- The broader `OnboardingCoordinatorTests` filter was interrupted after approximately two minutes because unrelated asynchronous onboarding tests did not complete; it emitted no failure and is not claimed as passing evidence.
- `git diff --check` passed.

## Verifier plan

1. Rebase onto the current authoritative root and rerun the two exact focused tests.
2. Install a fresh signed QA candidate under the serialized runtime lease.
3. On the Schedule step, select a non-default weekday subset, use non-default exact minutes, and configure an overnight quiet window.
4. Confirm the accessible summary names the day count, overnight semantics, and timezone, then continue.
5. Relaunch and verify the selected weekdays and exact boundaries reload unchanged.
6. Confirm deselecting the final weekday blocks Continue with the exact recovery message.
7. Only after the signed journey passes, update tracker, registry, backlog, and Lavish from the verifier lane.
