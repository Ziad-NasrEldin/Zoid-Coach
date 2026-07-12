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

`swift test --filter PlanningCapacityStateTests` passed six focused tests.

`swift test --filter "PlanningCapacityStateTests|SourceHealthTests|QAFixtureOSCompositionTests"` passed the focused capacity tests plus the affected Calendar composition and source-health coverage.

The focused build compiled `AppModel`, `DashboardView`, `CalendarService`, `QAFixtureOSServices`, and the new capacity state under the app's macOS target.

`git diff --check` passed.

## Independent verification

The verifier fixed two end-user blockers before packaging.

The panel had been mounted only when no Today snapshot existed, which hid it during normal signed operation.

The Calendar commitment count was not published independently, which could leave a live panel stale when availability remained in the same state.

The corrected signed QA package built, passed code-signing verification, installed under the QA identity, registered its isolated helper, and opened the normal snapshot-backed Today surface.

The installed panel visibly showed `0 MIN PLANNED / 126 MIN AVAILABLE` from two overlapping external Calendar commitments clipped to the configured work window while a Zoid-owned block was excluded.

The same panel visibly appeared inside normal snapshot-backed Today, proving the visibility blocker is fixed.

## Remaining installed proof

The seeded fixture was accepted after its required Calendar participant field was corrected, but the isolated helper snapshot did not refresh the seeded Reminders into the visible Today inventory after helper re-registration.

The verifier therefore did not claim the populated overload, direct reduction, estimate change, realistic approval, or relaunch sequence.

`ZC-009-001` through `ZC-009-008` remain conservatively unchecked as `Touches remaining` until that single installed journey passes.

The full Swift runner entered the separately documented idle-helper condition and was sampled and terminated once without a pass claim.

The signed package build and focused affected suites passed.
