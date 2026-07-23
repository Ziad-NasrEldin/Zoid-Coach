# Clock-Safe Task Durations Candidate

## Scope

This candidate hardens `ZC-053-011` without changing the tracker, registry, Lavish audit, runtime fixtures, or task presentation surfaces.

## User behavior

- Moving the wall clock backward cannot create a negative visible task duration.
- Closing an interval after a backward clock change persists the start instant as its earliest valid end instead of storing an end before the start.
- Moving the wall clock far forward cannot add more than 24 hours to one continuous interval.
- Legitimate accumulated time across separate start, pause, resume, and task-switch intervals remains additive.
- The normalized duration remains stable after reopening the database.

## Verification

- `backwardClockChangeNeverPersistsOrDisplaysNegativeTaskTime` passed.
- `forwardClockJumpCapsOneContinuousIntervalAtOneDayAcrossRestart` passed.
- `startingAnotherTaskAtomicallyPausesTheExistingTask` passed.
- `pausedTaskRestoresElapsedTimeWithoutDoubleCounting` passed.
- `swift build -c release` passed.

## Verifier handoff

Independent signed verification should start a controlled task, simulate a backward and a large forward wall-clock discontinuity through an isolated time source, and confirm the visible elapsed time stays between zero and 1,440 minutes for that continuous interval across app and helper restart.
