# Compact Active Task Verification

## Verdict

`ZC-037-006` advances from Not implemented to Touches remaining.

The compact menu presentation, focused state and lifecycle proof, release package, and signed active-task setup pass.

The macOS status item did not open through the available native accessibility or frame boundary, so visible compact-popover and control acceptance remains incomplete.

## Revisions

- Authoritative base: `dc83239`.
- Rebased candidate: `8c9846c`.
- Verifier accessibility fix: `e1558ea`.

## Automated proof

- The exact five focused tests passed after the one-time rebase.
- The verifier removed duplicate VoiceOver title and timing announcements from the compact non-control header.
- The compact header now exposes one stable `menu-bar.task.summary` node.
- The deadline test now checks the exact formatted fact instead of only a `Due` prefix.
- One QA release package passed app and helper builds, package coherence, signing, LaunchAgent, and Mach-service validation.

## Signed runtime proof

- A fresh isolated ready-state opened Today in a non-minimized 1180 by 760 window with 111 accessibility nodes.
- Native controls selected unplanned work and started `qa-ready-task`.
- The canonical database contained one open task activity interval for `qa-ready-task`.
- Native AX exposed the real app status item as an `AXMenuBarItem` titled `A task is active`.
- The status item reported the `AXPress` action and a concrete native frame.
- Invoking `AXPress` returned `-25205` and did not open the compact popover.
- The single permitted frame-based native click opened Notification Center rather than the Zoid 666 compact surface.

## Remaining acceptance

No compact-popover pixel or native-control claim is made.

The signed run did not prove the compact title, estimate, urgency, deadline, main-objective, locked, or blocked variants inside the popover.

It also did not click Pause, Break, Complete, Resume, End Break, Start, or End Workday in the compact surface, or prove those states across app and helper relaunch.

A later verifier needs a harness that can reliably open the SwiftUI `MenuBarExtra` rather than targeting the adjacent Notification Center region.
