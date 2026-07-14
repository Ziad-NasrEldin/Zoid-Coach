# ZC-034-011 Independent Scroll-Path Verification Result

## Verdict

The signed runtime remains inconclusive and `ZC-034-011` must remain `Touches remaining`.
This run found no new product failure.
It did not prove the complete Save Blocker journey.

## Package and isolation

The exact prepared package identity was `zoid-coach-f28ad1087623bd308fc410f78ab6215cf1b69131-clean`.
Deep strict code-sign verification passed before every launch.
The app executable SHA-256 remained `2012d1dea61ea8c8cb1e5e2ad995d879f752da0b62460fcb499abac55f6aa748`.
The helper executable SHA-256 remained `bfcc3343ab964e9b56cfa876d819308ce1204df9f4da63d1ddfc1a5f978ac9c8`.
Every successful registration resolved the helper executable inside the isolated signed app and reported a writable prompt timeline.

## Verified preconditions

The isolated Today window opened at `1180x760` with 176 native accessibility content nodes.
The fixture contained prompt `qa-block-1` in `presented` state with exactly six direct action buttons and zero responses.
Task `task-1` was active, was the main objective, and had one open activity interval.
Task `task-2` was the eligible replacement objective.
The Mark blocked button frame was `{{977, 2061}, {905, 28}}` while the visible content frame was `{{738, 237}, {1164, 672}}`.
The verifier correctly classified the button center as outside the visible viewport and never clicked that off-screen coordinate.

## Scroll-path result

The verifier tried physical wheel scrolling, foreground Page Down input, the native `AXScrollToVisible` action, and the scroll area's vertical scrollbar value.
The SwiftUI Today scroll surface did not move under those injected inputs in this automation session.
The verifier therefore never issued the Mark blocked click and did not confuse an off-screen click with product behavior.
The blocker sheet, preset Save, exact database mutation, replacement-main promotion, relaunch persistence, and helper-down restoration were not reached.

## Runtime irregularity

One failed preparation attempt created a database before the `source_kind` migration became observable, even though registration had returned success.
A later attempt also found a background-schedule process from the isolated install still alive after the original exact-name cleanup.
Neither condition touched canonical user data.
The verifier harness now also kills the exact isolated executable path during cleanup.

## Cleanup

The isolated foreground and background app processes were force-stopped.
The isolated helper process and LaunchAgent were removed.
The isolated installed app and QA root were removed.
No canonical repository, tracker, registry, Lavish artifact, or user database was modified.

## Recommendation

Keep `ZC-034-011` at `Touches remaining`.
Do not classify the off-screen state as a product defect.
The next acceptance should use a human-visible mouse or trackpad scroll through the Today window, or a verifier attached to the user's real GUI session that can deliver trusted scroll input, before exercising the remaining Save, persistence, and helper-down assertions.
