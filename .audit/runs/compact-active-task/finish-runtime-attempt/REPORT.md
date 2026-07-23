# ZC-037-006 Signed Runtime Attempt

## Verdict

The exact candidate packaged, signed, installed, and launched in an isolated QA runtime.

The capped run did not reach the compact menu surface, so `ZC-037-006` remains Touches remaining and no tracker transition is justified.

## Revision

- Candidate: `a9bf37a656fee995096b742558f0b14834ed7054`.
- QA root: `/private/tmp/zoid-666-compact-finish-qa`.
- Install root: `/private/tmp/zoid-666-compact-finish-install`.

## Evidence

- The exact clean candidate passed release QA packaging and created `Zoid 666 QA.app`.
- The signed runtime installer registered and launched the isolated QA helper and application.
- The first foreground launch visibly rendered the complete Setup 1 of 12 window because the installer correctly performed its clean-root step after the ready-state root had been prepared.
- The first-launch screenshot is `/private/tmp/zoid-666-compact-finish-today.png` while that temporary evidence remains available.
- The verifier stopped the app and helper, re-prepared the isolated ready-state root, kicked the exact QA LaunchAgent, and relaunched the installed application.
- The relaunched process entered its background/no-on-screen-window state before Today and the status item could be inspected.
- The ten-minute runtime cap then expired.

## Unproven Boundaries

- No compact-menu pixel or accessibility claim is made.
- No native menu action was clicked.
- No live elapsed-time, Pause, Resume, Complete, Blocked, helper-failure, or relaunch-persistence claim is made from this runtime attempt.
- The generic privacy-safe status label remains proven by focused public-interface tests, not by a native installed status-item capture.

## Cleanup

The signed QA runtime was uninstalled, the app and helper were stopped, the QA root and install root were removed, and the runtime lease was released at the cap.
