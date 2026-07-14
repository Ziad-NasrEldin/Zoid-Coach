# ZC-024-008 independent signed verification

## Verdict

ZC-024-008 is not eligible for Fully implemented from this run.

The focused product tests and signed runtime infrastructure passed, but the required installed MenuBarExtra journey did not reach the three distinct time elements.

The real installed status item exposed `A source needs attention` instead of `A task is active`.

The generated Today snapshot contained the fixture active interval but had an empty `taskRows` array, so the menu-bar state could not resolve an active task row and the AX verifier correctly stopped at the status-item gate.

## Candidate identity

- Canonical base: `824e29a9a9fa94908230d430c4bdbf78236834ea`
- Product candidate layered as explicit commit: `ea4ac7c`
- Verifier tooling layered as explicit commit: `ee102ec`
- Combined clean candidate: `ee102ec5999f060cfb379b0581d5ada0555f82ba`
- Original product commit: `5accf2dac689797c39b7e409270fffddce1ad229`
- Original verifier commit: `7ab6238392a1ec3c76b13966fb4f8dd730aeba6a`

## Passed gates

- Fresh detached worktree created from the requested canonical base.
- Product and verifier commits applied cleanly as two explicit commits.
- All four `MenuBarActiveTimeComparisonTests` passed.
- The fixture self-test passed and preserved foreign rows.
- Release QA package completed from the clean combined candidate.
- Deep strict code-sign verification passed for the installed app and nested helper.
- Package verification passed for QA mode, the exact combined commit, clean state, LaunchAgent identity, Mach service, and signing identities.
- The installed QA app launched from `/private/tmp/zoid-666-zc024008-install/Zoid 666 QA E2E.app`.
- QA LaunchAgent `qa.ziadnasreldin.ZoidCoach.agent` ran from the installed bundle.
- QA registration reported a writable XPC runtime and prompt timeline.
- The canonical agent heartbeat existed at `2026-07-14T16:10:18Z`.
- The namespaced fixture created one active task interval, five aligned work observations, and the expected minimum elapsed value of 14 minutes.

## Failed or unproven gates

- Baseline installed MenuBarExtra AX probe: failed before opening the compact card because no `A task is active` status item was available.
- Distinct `menu-bar.task.elapsed-time`, `menu-bar.task.aligned-time`, and `menu-bar.task.alignment-evidence` elements: not reached.
- Truthful visible values and AX hints: not reached.
- Elapsed time continuing independently from stable aligned time through app and helper relaunch: not reached.
- Missing producer data remaining absent while explicit zero evidence remains truthful in the installed UI: covered by focused tests only, not proved in the signed UI.
- Private fixture values absent from the installed accessibility surface: the target surface was not reached, so this UI privacy gate remains unproved.

## Acceptance blocker evidence

The real accessibility tree exposed one status item with:

- Role: `AXMenuBarItem`
- Title: `A source needs attention`

The current Today snapshot contained:

- `activeTask.taskID = qa-zc024008-active-task`
- `activeTask.elapsedMinutes = 16`
- `taskRows = []`
- Reminders source state `not_connected`
- Calendar source state `not_connected`
- Screenwatch source state `current`
- Agent source state `running`

Because `MenuBarCoachState` resolves the active presentation through a matching task row, the empty task-row collection prevented the installed menu bar from presenting the active-task comparison.

## Cleanup and production safety

- Fixture cleanup and a second `verify-clean` both passed.
- QA private sentinel count was zero before removing the isolated runtime.
- QA LaunchAgent was absent after cleanup.
- Isolated QA app was absent after cleanup.
- Isolated QA runtime root was absent after cleanup.
- Production database contained zero `qa-zc024008-*` fixture rows.
- Canonical source, tracker, registry, production app, and production database were never written by this verifier.

## Strict next gate

Provide a signed QA state where the active fixture task is also present in `taskRows`, then rerun the unchanged native AX probe for baseline and relaunch.

Do not promote ZC-024-008 until all three accessibility elements, truthful help text, advancing elapsed time, stable aligned time, relaunch persistence, zero and missing producer semantics, and UI privacy are observed in the installed app.
