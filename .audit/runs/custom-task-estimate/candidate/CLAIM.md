# Custom task estimate claim

This isolated lane starts from authoritative commit `8354fef`.

Higher ready implementation items require serialized runtime proof or overlap the active onboarding schedule-window validation, so this lane pulls priority 14.

## Scenarios

- `ZC-011-006` - Enter a custom estimate.
- `ZC-011-007` - Receive a clear error for an empty, zero, negative, or malformed estimate.

## Owned files

- `Sources/ZoidCoachApp/TaskEstimateInput.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Tests/ZoidCoachAppTests/TaskEstimateInputTests.swift`
- `.audit/runs/custom-task-estimate/candidate/*`
- The isolated backlog claim and handoff rows only.

The lane will add a keyboard-accessible custom-minute estimate path with strict bounded validation, precise errors, cancellation, and the existing durable plan-update callback.
It will not touch onboarding schedule files, runtime, tracker, registry, or Lavish.
