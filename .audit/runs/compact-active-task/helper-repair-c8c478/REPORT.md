# ZC-037-006 Compact Helper Repair Acceptance

## Verdict

`ZC-037-006` remains Touches remaining.

The shared runtime-boundary repair closed the earlier signed helper mismatch for an active task.

The exact installed compact popover refreshed from the same QA helper truth as Today and exposed the active task with Pause, Break, Complete, Blocked, Open Today, and End Workday controls.

The signed Pause action persisted canonical paused state, but reopening the compact popover showed an empty task state instead of the paused task and Resume action.

The end-user journey therefore remains incomplete.

## Revision And Package

- Canonical source revision: `c8c478a8d16665e654de1aa4d52dcf4fb2656f35`.
- Packaged build identity: `zoid-coach-c8c478a8d16665e654de1aa4d52dcf4fb2656f35-clean`.
- Installed application PID: `26809`.
- Isolated application root: `/private/tmp/zoid-666-compact-helper-c8c478-install`.
- Isolated QA data root: `/private/tmp/zoid-666-compact-helper-c8c478-qa`.

## Focused Verification

The candidate initially failed the new regression because `adoptLastKnownSnapshot` could replace newer confirmed controller truth with a delayed fallback snapshot.

The minimal correction accepts a fallback only while the compact controller has no snapshot.

`swift test --filter MenuBarCoachTests` then passed all 27 selected tests.

The tests cover the shared runtime boundary, active and paused state, break and resume, completion, blocked-reason confirmation, helper failure, persistence, privacy-safe status copy, and the non-overwrite regression.

## Signed End-User Evidence

The signed QA installer passed package verification, writable XPC registration, helper launch, and canonical runtime heartbeat checks.

The exact PID's native status item opened a visible 360-point `AXSystemDialog` compact popover.

The public Open Today control opened the installed Today surface.

The public `planning.unplanned.start.qa-ready-task` control started `Verify the ready-state journey`.

After Refresh, the compact popover displayed `Active - Open-ended - 0 min tracked` and exposed the complete active action set.

The status item and compact status remained privacy-safe and did not expose the private task title outside the opened popover.

Pressing the signed compact `menu-bar.task.pause` control succeeded.

The canonical database recorded `qa-ready-task` as `paused`, closed its activity interval once, and recorded one `doneForNow` pause event.

Reopening the same PID's compact popover then displayed `No task is active or ready` and exposed no Resume action.

No Resume, Complete, Blocked-reason, helper-failure stale-state, or relaunch-persistence claim is made from this run.

## Remaining Work

The compact snapshot composition must retain an unplanned paused task returned by the canonical helper.

The corrected signed journey must then prove Pause, reopen, Resume, Complete, Blocked with an exact reason, helper-failure stale preservation, and app/helper relaunch persistence through the native compact surface.

## Cleanup

The signed QA runtime was unregistered and removed within the runtime cap.

The QA application, helper processes, installed application root, and QA data root were absent after cleanup.
