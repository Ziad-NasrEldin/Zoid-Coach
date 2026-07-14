# ZC-037-006 Paused Compact Task Retention Acceptance

## Verdict

`ZC-037-006` remains Touches remaining.

The signed native journey now proves that an unplanned task survives Pause, compact-popover reopen, Resume, and application relaunch without losing its identity or canonical timing state.

The accumulated evidence does not yet execute native Complete, native Blocked with a reason, or helper-failure stale-state preservation through the installed compact surface.

## Revision And Package

- Verified source revision: `2a11918c7e136d757a57090f7ccd9b1297b037aa`.
- Installed application: `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app`.
- Initial application PID: `83540`.
- Relaunched application PID: `10706`.
- Helper PID across relaunch: `83539`.
- Isolated QA data root: `/private/tmp/zoid-666-zc037-pause-qa`.

## Focused Verification

Five focused compact-menu and durable-command tests passed.

The selected tests covered paused-task reopening, the truthful paused action set, confirmed blocked presentation, completion through the canonical command boundary, and persistent Break and End Workday commands.

The release QA installer passed package verification, code signing, writable XPC registration, helper launch, and runtime heartbeat checks.

## Signed End-User Evidence

The installed Today surface started `Verify compact pause ownership` while `Keep this unrelated reminder queued` remained unplanned.

The exact application PID's native status item opened a visible compact popover containing the exact focus task.

The active compact surface exposed Pause, Break, Complete, Blocked, Open Today, and End Workday.

The unrelated reminder did not replace or appear as the compact task.

Pressing `menu-bar.task.pause` succeeded on the signed native control.

The canonical database changed only `zc037-focus` to paused, closed its one open activity interval once, and recorded a `doneForNow` pause event.

Reopening the same PID's status item displayed `Verify compact pause ownership. Paused because you are done for now. 30 min estimate. Low urgency`.

The paused surface exposed only Resume, Blocked, and Open Today task controls.

Pressing `menu-bar.task.resume` succeeded on the signed native control.

The canonical database restored the exact task to active, marked the pause event resumed, and opened a second activity interval.

After terminating and reopening only the application, the helper stayed alive, the application received a new PID, and the compact surface restored the exact active task with the full active action set.

## Remaining Acceptance

Run native Complete and verify that the compact task disappears while durable completion state remains correct.

Run native Blocked, provide an exact reason, and verify the confirmed blocked presentation and persistence.

Interrupt helper availability and prove that the compact surface preserves last-known truthful state without inventing fresher data.

## Cleanup

The installed signed QA runtime and its application and helper processes were removed within the runtime cap.

The isolated QA data root was retained temporarily for audit inspection.
