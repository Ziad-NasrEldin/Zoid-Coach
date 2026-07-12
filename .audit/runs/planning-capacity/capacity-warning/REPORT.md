# Planning Capacity Warning Implementation Evidence

## Scope

This batch implements `ZC-009-001` through `ZC-009-008` without changing the scenario tracker, registry, migrations, weekly review, daily review, or agent lifecycle files.

The Today plan now compares the selected workload with available focus capacity in one visible panel.

Available capacity uses the current work-window policy, its planning-capacity percentage, merged non-Zoid Calendar commitments clipped to configured work intervals, and the user's visible-calendar selection.

When Calendar cannot be read, the UI explicitly says that it is using configured work-window capacity instead of silently claiming Calendar-adjusted availability.

## End-user behavior

- An empty plan explains how to begin capacity evaluation.
- A plan with missing estimates names the exact number of tasks that still require estimates.
- An overloaded plan shows planned minutes, available minutes, and the exact overage.
- The warning names the lowest-ranked task as a concrete reduction suggestion.
- The user can remove that task directly from the warning.
- Estimate changes and plan additions or removals recalculate the panel immediately from published plan state.
- Calendar acceptance stays disabled until every task is estimated and the plan fits capacity.
- A realistic revision receives an explicit ready-to-accept confirmation.
- Calendar occupancy merges overlapping meetings, clips events to work hours, excludes Zoid-owned work blocks, and respects selected visible calendars.

## Verification

`swift test --filter PlanningCapacityStateTests` passed five focused tests.

`swift test --filter "PlanningCapacityStateTests|SourceHealthTests|QAFixtureOSCompositionTests"` passed the focused capacity tests plus the affected Calendar composition and source-health coverage.

The focused build compiled `AppModel`, `DashboardView`, `CalendarService`, `QAFixtureOSServices`, and the new capacity state under the app's macOS target.

`git diff --check` passed.

## Deliberately deferred proof

This lane did not run a release build, signed-QA package, helper registration, or visible installed-app click-through because the weekly release verifier owns the exclusive package and runtime lease.

A fresh verifier must seed an over-capacity QA plan, click the reduction action, change an estimate, confirm immediate recalculation, accept the realistic revision, and update the authoritative tracker only after that installed-product proof passes.
