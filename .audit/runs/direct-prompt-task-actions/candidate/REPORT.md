# Direct Prompt Task Actions Candidate Report

`ZC-034-011` is ready for another constrained signed installed journey.
This candidate fixes the exact accessibility boundary reported by the prior verifier.

## Root cause and change

The task-change group placed Reschedule and Mark blocked inside an adaptive `LazyVGrid`.
The signed accessibility tree exposed that grid as a collection with no button children even though the controls were visibly rendered.
An end user relying on accessibility activation could not reach Mark blocked without a coordinate guess.

The task-change label remains directly below the prompt summary.
The two unique task-change buttons now render directly in the prompt row's view hierarchy with full available width.
No virtualized collection or task-change container sits between the prompt row and those buttons.
The stable action identifiers, blocker-opening hint, reason sheet, validation, Cancel, mutation ordering, and failure preservation remain unchanged.
The recovery actions keep their adaptive grid because the reported blocker was limited to the high-priority task-change controls.

## Focused proof

`swift test --filter PromptTaskBlockState` passed.
The focused suite proves that the exact six-action prompt partitions into two task changes and four recovery actions without missing or duplicate identifiers, and retains the 3-to-240-character reason contract.
`swift build -c release` passed.

## Independent signed acceptance

Load the exact six-action numeric-flag gaming-drift fixture in the same constrained Today window.
Inspect the accessibility tree and confirm `today.prompt.<id>.action.reschedule_task` and `today.prompt.<id>.action.mark_blocked` are direct reachable buttons rather than children of an empty collection.
Activate Mark blocked through accessibility, not coordinates.
Submit a too-short reason and confirm the task and prompt remain unchanged.
Cancel and confirm the same unchanged state.
Save a meaningful reason and confirm the active task becomes blocked, its interval closes, the ready replacement becomes main, and the prompt appears once in answered history.
Restart the app and helper and confirm persistence.
Repeat with the helper unavailable and confirm the task plus prompt remain unchanged with a usable retry message.
