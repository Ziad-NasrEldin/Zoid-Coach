# Unplanned Apple Reminder Completion Follow-up Verification

## Result

`ZC-021-002` remains Partially implemented.

The repaired signed journey now keeps the externally completed unplanned task visible across refresh, relaunch, and later source deletion, but the UI labels it only `Completed` instead of explaining that Apple Reminders ended it.

## Automated proof

- Four focused tests passed for unplanned completion restoration, interval and sprint ending, duplicate-history prevention, and completed-then-deleted ordering.
- One release package passed app and helper builds, package coherence, signing, LaunchAgent, and Mach-service validation.

## Signed journey

- The installed signed QA app opened Today at 1180 by 760 pixels with 118 accessibility nodes.
- Native controls started the unplanned `qa-ready-task` through the installed helper.
- The isolated source fixture then marked that Apple Reminder complete and left `qa-next-task` available.
- After helper consumption and app relaunch, Today retained `Verify the ready-state journey` as `Completed` and kept `Continue with the next task` available.
- The database contained one interval for `qa-ready-task`, with one ended interval and zero open intervals.
- Exactly one Reminder-source completion history row existed.
- Zero `completeReminder` action commands existed for the task.
- A second fixture mutation deleted `qa-ready-task` from the source, and the completed Today row still survived another relaunch through the durable completion tombstone.
- The signed journey did not create a sprint, so signed sprint-ending acceptance remains unproven even though the focused persistence test passed.

## Remaining usability blocker

The visible row says only `Completed`.

It does not expose `Ended because the Apple Reminder was completed`, so an end user still cannot understand why the active task ended without inferring it from external context.

## Evidence

- `today-ready-state.png` records the native Today surface before the external completion mutation.
- The authoritative tracker and registry retain Partially implemented status and unchanged scenario counts.
