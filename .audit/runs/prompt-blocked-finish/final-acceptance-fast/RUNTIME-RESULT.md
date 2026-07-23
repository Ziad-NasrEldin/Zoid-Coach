# ZC-034-011 Final Signed Runtime Result

## Verdict

`ZC-034-011` is not independently accepted as fully usable end to end by this run.
It remains `Touches remaining` and the tracker must not be promoted.

## Signed runtime that passed

The runtime used exact package identity `zoid-coach-f28ad1087623bd308fc410f78ab6215cf1b69131-clean`.
Deep strict code-sign verification and the designated requirement passed for both the package and isolated installed copy.
Each helper registration reported a writable XPC prompt timeline and canonical heartbeat.
The helper executable resolved exactly inside the isolated installed signed app.
The canonical ready-state fixture opened Today in a non-minimized `1180x760` window with 176 native accessibility content nodes.
The seeded SQLite state contained `qa-block-1` as a presented `GAMING_DRIFT` prompt with six actions and zero responses.
It also contained `task-1` as the active main objective with one open interval and `task-2` as the replacement candidate.
The accessibility tree exposed exactly six direct `today.prompt.qa-block-1.action.*` buttons.

## Concrete acceptance failure

The visible screenshot showed the Today page at the upper dashboard and active-commitment region, while the coaching decision actions were below the current viewport.
The Mark blocked accessibility node reported a physical center at `(1429, 2075)`, outside the captured `1180x760` window viewport.
Native `AXPress` returned success on that node, but the blocker sheet and approval preset did not become reachable.
The one approved AX-located physical click also targeted `(1429, 2075)` and did not make the blocker sheet or approval preset reachable.
The verifier stopped after that bounded retry as instructed.
It did not claim a valid Save Blocker mutation, exactly-once response, blocked history, replacement-main promotion, app/helper relaunch persistence, or helper-unavailable failure preservation.

## Evidence

The pre-action pixel capture is `evidence/success-actions.png` with SHA-256 `37d1b504addb05d788dea3b5784752cb762aff3ce2a512a6befb575a131b68d0`.
The exact pre-action database state is `evidence/success-seed.json`.
Registration continuity is recorded in the three `success-*-registration.txt` and `install-registration.txt` files.
The accumulated native runtime milestones are recorded in `evidence/runtime.log`.
The final concise result is recorded in `evidence/final-result.txt`.

## Cleanup

The final harness exit removed the isolated installed app and QA root.
The QA LaunchAgent was absent after cleanup.
No ZoidCoach QA app or helper process remained.
The canonical repository, tracker, registry, Lavish artifact, user data, and unrelated runtimes were untouched.
Approximately 11 GiB remained available after cleanup.

