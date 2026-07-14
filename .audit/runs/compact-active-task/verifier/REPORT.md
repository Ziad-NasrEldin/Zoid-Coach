# ZC-037-006 Compact Active Task Independent Verification

## Verdict

`ZC-037-006` remains at Touches remaining.

The compact state model, live elapsed calculation, deduplicated state-specific actions, required blocked-reason confirmation, stale and unavailable truth, persistence reload, privacy-safe status label, and two-column layout have source and focused automated proof.

Independent review found and fixed one end-user defect where a successfully blocked task disappeared from the compact menu immediately after the helper confirmed the mutation.

Signed native acceptance of the actual status item and compact popover is still required before this scenario can be called fully usable end to end.

## Revision Lineage

- Authoritative base: `2596f6e9c60bb6a7fad8f85003ccf17dea765236`.
- Transplanted candidate: `eb99033` from `a9bf37a656fee995096b742558f0b14834ed7054`.
- Transplanted runtime attempt: `cb7d9dd` from `ea0bee91ed755a01173fb804bdff7e34505ed860`.
- Independent correction: `d6bae8e92ec159921f37d4c24f2f825f9ea5834a`.

## Independent Finding And Correction

The public block boundary correctly required a trimmed 3-to-240-character reason and accepted only a returned row whose task identifier, `.blocked` state, and normalized reason exactly matched the request.

However, `MenuBarCoachState` selected only active, paused, or ready rows as its primary compact task.

The confirmed `.blocked` row therefore disappeared from the compact menu even though the controller held the correct persisted response.

The correction selects a blocked row as the compact primary task, presents an attention tone and the confirmed blocked reason, and exposes only Open Today because Resume, Pause, Complete, Break, and Block Again would be false for that state.

A focused regression test now proves the blocked task identifier, reason, accessibility summary, tone, and exact nonduplicated action list.

## Verified Source Behavior

- Active tasks expose Pause, Break 15, Complete, Blocked, Open Today, and End Workday exactly once.
- Paused tasks expose Resume or End Break, Blocked, and Open Today without active-only commands.
- Recommended ready tasks expose Start, Blocked, and Open Today.
- Confirmed blocked tasks remain visible with the exact persisted reason and only Open Today.
- Live elapsed time advances from the open interval while retaining time accumulated before that interval.
- Backward clock movement cannot reduce the last confirmed elapsed duration.
- A first helper failure reports unavailable state without inventing task truth.
- A later helper or mutation failure preserves the last confirmed snapshot and marks it stale.
- Relaunch coverage creates a new helper-equivalent agent and controller, then restores the ended-workday task, Resume action, and saved duration from canonical persistence.
- The status-item accessibility label remains generic and does not include the private task title.
- The compact controls use a two-column flexible grid.

## Automated Evidence

- `swift test --filter MenuBarCoachTests` exited successfully after the independent correction.
- `swift build -c release` exited successfully under the transferred build lease.
- `git diff --check` passed before the correction commit.
- Free disk before the build was 2.6 GiB, above the 400 MiB stop threshold.

## Prior Signed Runtime Evidence Reviewed

The prior exact-candidate attempt packaged, signed, installed, and launched an isolated QA application and helper.

That attempt did not reach the compact menu because the clean install removed the preprepared ready-state root, and the later re-preparation ended with the application backgrounded before status-item inspection.

An earlier verifier observed the real `AXMenuBarItem` titled `A task is active`, its `AXPress` action, and a concrete native frame.

That verifier could not open the SwiftUI `MenuBarExtra`, and its permitted frame click opened Notification Center instead.

No compact-popover pixel or native-control claim is inherited from either attempt.

## Remaining Signed Acceptance

- Package and install the exact clean independent revision while holding the serialized runtime lease.
- Prepare the isolated ready-state fixture after the installer's clean-root step.
- Open the real Zoid 666 status item through a reliable native AX or coordinate boundary.
- Capture compact-popover pixels and AX nodes for the title, live timing, facts, and two-column action layout.
- Observe elapsed time advance in the open popover.
- Click Pause, Resume, Blocked with a required reason, and one terminal action through the compact surface.
- Confirm the blocked response remains visible with the exact reason.
- Force a helper failure and prove the last confirmed task remains visible as stale.
- Relaunch the app and helper and prove the exact task state and saved duration persist.
- Confirm the native status item uses only the generic privacy-safe label.

No tracker update or Full claim is justified until that signed journey succeeds.

## Capped Signed Runtime On 14 July 2026

The exact clean verifier tip packaged, signed, installed, and launched as an isolated QA application and helper.

The installer completed before ready state was prepared, avoiding the earlier clean-root loss.

The helper was unregistered, the canonical ready-state manifest was atomically prepared, and the exact installed helper and application were registered and relaunched.

Native AX confirmed Today in a non-minimized 1180 by 760 window with 112 content nodes.

The public unplanned-work control `planning.unplanned.start.qa-ready-task` started the fixture task successfully.

The installed main surface exposed the exact title and advanced from zero to one tracked minute without another mutation.

The native status-item label changed to `A task is active` and did not expose the private task title.

System Events exposed the status item as the application's only item in menu bar 2 and accepted a click.

After the main window was closed, that click created a separate `AXSystemDialog` window at 360 by 490 points.

The system-dialog window rendered fully transparent in the captured pixels and exposed no usable compact descendants to the verifier's AX traversal.

Pause, Resume, Complete, Blocked, Open Today, blocked-reason persistence, helper-failure stale truth, and app/helper relaunch could not be exercised through the invisible compact surface before the ten-minute cap.

The runtime evidence is preserved under `runtime/` with the ready Today screenshot, ready-state AX dump, active-task AX dump, and transparent status-item screenshot.

At the cap, the signed runtime was uninstalled and the isolated application, helper, LaunchAgent, QA root, and install root were removed.

No QA application or helper process remained, and launchd reported that the QA service did not exist.
