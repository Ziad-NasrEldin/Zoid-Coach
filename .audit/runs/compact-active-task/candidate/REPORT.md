# Compact Active Task Candidate

## Scope

This candidate implements `ZC-037-006` without changing the authoritative tracker, registry, Lavish audit, runtime fixtures, or app model.

## User behavior

- The menu-bar task card keeps the active task title and live active, sprint, accepted-break, paused, or ended-workday status visible.
- The compact card now also exposes main-objective status, estimate, urgency, deadline, locked state, and blocked reason.
- One combined accessibility label announces the title, live task status, and every compact fact once without requiring the user to open Today.
- Existing Pause, Break, Complete, Resume, End Break, Start, and End Workday actions continue through their canonical durable command boundaries.
- Recommended and paused tasks use the same factual presentation without inventing unavailable state.

## Verification

- `compactActiveTaskKeepsEssentialStateVisibleAndAccessible` passed.
- `compactTaskFactsExposeLockedAndBlockedStateWithoutInventingIt` passed.
- `menuBarStateDistinguishesNeutralAttentionActiveAndPaused` passed.
- `activeMenuTaskCompletesThroughTheSameDurableCommandBoundary` passed.
- `menuBarControllerRunsBreakResumeAndConfirmedEndWorkdayJourney` passed.
- `swift build -c release` passed.

The focused tests cover the compact presentation model and command lifecycle.

Visible layout and the combined native accessibility node remain assigned to signed verifier proof.

## Verifier handoff

Independent signed verification should start a task, open the menu bar, and confirm the compact card exposes the title, active elapsed or sprint state, estimate, urgency, deadline when present, main-objective state, and task actions through native accessibility and pixels.

The verifier should then exercise Pause, Resume, Break, End Break, Complete, and End Workday without losing the compact task state.
