# Menu Bar Task Controls Candidate

## Scope

This candidate implements the primary menu-bar journey for `ZC-023-001`, `ZC-023-002`, `ZC-023-003`, `ZC-023-005`, `ZC-023-006`, `ZC-023-007`, `ZC-023-011`, and `ZC-023-012`.
It deliberately leaves break sessions, coaching pause, and end-of-workday behavior to their owning future models rather than presenting controls that cannot yet work end to end.

## Implementation

- The menu icon now reflects neutral, active, paused, or source-attention state from the canonical Today snapshot.
- The popover shows the active, paused, or recommended task with exact tracked or sprint state.
- Start, Pause, and Resume run through the authenticated Today XPC client and return the newly persisted canonical snapshot.
- A failed mutation preserves the last confirmed state and gives a direct Source Health recovery message.
- Open Today, Source Health, and Settings activate the main app and select the exact destination.
- Refresh reloads both the popover snapshot and the main application model.
- Existing voice controls remain available in a separate disclosure below the task controls.
- Stable accessibility identifiers cover status, task state, start, pause, resume, navigation, attention, refresh, empty, and error states.
- No migration, Dashboard, AppModel, AgentMain, baseline, or coaching-policy file was changed.

## Focused proof

`swift test --filter MenuBarCoach` passed.
The focused suite proves neutral, attention, active, paused, recommendation selection, optional-task exclusion, start persistence response, pause failure recovery, and command ordering.
The app target compiled through the focused test build.

## Remaining verifier work

A fresh verifier must package and install signed QA, seed neutral, recommended, active, paused, and unhealthy-source snapshots, click Start, Pause, Resume, Today, Source Health, and Settings, and confirm restart persistence.
The tracker and registry remain unchanged until that visible verification passes.
