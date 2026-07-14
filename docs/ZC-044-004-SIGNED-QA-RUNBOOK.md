# ZC-044-004 signed QA runbook

This runbook verifies manual workday start and end against the exact installed signed candidate.
It uses the production policy, local-task, daily-plan, task-execution, activity-interval, and pause-event schemas.
The fixture owns only the `qa-zc044004-*` task namespace and records the original active policy version for cleanup.

## Preconditions

Use an isolated QA database and install root.
Confirm the installed application identity resolves to candidate `03ed2a30bb77c57a6f60b5102f3ae1b807ab75ae` or its accepted signed integration descendant.
Grant Accessibility permission to the terminal that runs the probe.
Do not continue if the fixture reports an ownership collision or schema mismatch.

Set these paths for the signed session:

```sh
APP="/absolute/path/to/Zoid 666.app"
DATABASE="/absolute/path/to/isolated/zoid.sqlite"
FIXTURE="Scripts/qa-zc044004-manual-workday-fixture.sh"
PROBE="Scripts/qa-zc044004-manual-workday-ax-probe.swift"
```

## Prepare the real policy and task state

Close the app before preparing the database.

```sh
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-prepared "$DATABASE"
open "$APP"
```

Open Settings in the signed app and leave the Command chapter visible.
Capture the signed build identity and the scheduled baseline before mutation.
Run the Settings probe against the exact installed process:

```sh
PID="$(pgrep -x "Zoid 666")"
swift "$PROBE" --pid "$PID" --phase settings-select-manual
"$FIXTURE" assert-manual "$DATABASE"
```

The probe selects `Manual start and end`, proves the fixed-hours group changes from enabled to disabled, presses the real Save Changes control, and waits for the saved confirmation.
The database assertion requires a newly versioned active policy with `schedule.workdayControlMode` equal to `manual` while preserving at least one planning window.

## Prove save and relaunch persistence

Quit the signed app normally and launch the exact same installed bundle again.
Open Settings and keep the Command chapter visible.
Confirm `Manual start and end` remains selected and fixed-hours controls remain disabled.

```sh
PID="$(pgrep -x "Zoid 666")"
"$FIXTURE" assert-manual "$DATABASE"
```

Record the Settings screenshot and AX evidence after relaunch.

## Prove manual start and confirmed end

Open the signed menu-bar popover before each probe phase.
The ready phase requires `START WORKDAY`, proves `END WORKDAY` is absent, and activates the real start control.

```sh
swift "$PROBE" --pid "$PID" --phase ready-start
"$FIXTURE" assert-active "$DATABASE"
```

Reopen the menu-bar popover after the task becomes active.
The active phase proves Start is absent, activates the real End Workday control, and presses the destructive confirmation.

```sh
swift "$PROBE" --pid "$PID" --phase active-end
"$FIXTURE" assert-ended "$DATABASE"
```

Reopen the menu-bar popover after the confirmed mutation.
The ended phase requires the ended status, requires both invalid Start and End actions to be absent, and requires the paused-task resume path to be labeled Start Workday.

```sh
swift "$PROBE" --pid "$PID" --phase ended
```

Quit and relaunch the exact signed app once more.
Open the menu-bar popover and repeat the ended probe.

```sh
PID="$(pgrep -x "Zoid 666")"
swift "$PROBE" --pid "$PID" --phase ended
"$FIXTURE" assert-relaunch "$DATABASE"
```

The database must still contain a manual active policy, a paused task, no open activity interval, and one open `endingWorkday` pause event.

## Cleanup

Close the signed app before cleanup.

```sh
"$FIXTURE" cleanup "$DATABASE"
```

Cleanup removes only the owned QA task rows and restores the original active policy pointer and payload.
Do not mark ZC-044-004 fully usable unless every fixture assertion and every AX phase passes against the same signed installed identity.
