# ZC-024-008 corrected-fixture signed rerun

## Strict verdict

ZC-024-008 is not yet eligible for Fully implemented from this capped rerun.

The corrected local-source fixture fixed the original task-row blocker and the baseline, relaunch, and explicit-zero installed MenuBarExtra journeys passed.

The hard ten-minute cap arrived before the missing-producer signed UI state and an independent accessibility privacy scan could be executed.

## Candidate

- Signed clean candidate: `1d621951eb45ff573798a1587bdcc00eac72e915`
- Base combined product and verifier candidate: `ee102ec5999f060cfb379b0581d5ada0555f82ba`
- Isolated runtime root: `/private/tmp/zoid-666-zc024008-rerun-runtime`
- Isolated install root: `/private/tmp/zoid-666-zc024008-rerun-install`

## Passed package and runtime prerequisites

- Release QA package completed from the clean exact candidate.
- Deep strict signing passed for the app and nested helper.
- Package validation passed for exact build identity, QA mode, LaunchAgent, Mach service, and signing identities.
- QA XPC registration reported a writable runtime and prompt timeline.
- The installed QA app launched from the isolated install root.
- The helper ran through the installed QA LaunchAgent.

## Passed corrected fixture gate

- The first seed attempt exposed a keep-alive SQLite race because killing the helper allowed launchd to restart it immediately.
- The supported `--qa-unregister-agent` lifecycle removed the race without altering product code or fixture contents.
- Fixture cleanup passed before reseeding.
- The corrected local-source fixture seeded successfully.
- The fixture verification reported a permission-independent local task source.
- The generated Today snapshot contained `qa-zc024008-active-task` inside `taskRows`.

## Passed installed MenuBarExtra gates

- Baseline native AX probe passed with elapsed 14 minutes and observed aligned 5 minutes.
- The probe required three distinct accessibility objects with identifiers `menu-bar.task.elapsed-time`, `menu-bar.task.aligned-time`, and `menu-bar.task.alignment-evidence`.
- Elapsed help identified the active task timer boundary.
- Aligned help and evidence disclosure stated that observed alignment is a signal, not proof of task match.
- App and helper relaunch restored the same signed presentation with elapsed 14 and aligned 5, proving non-regression and stable observed evidence.
- After the fixture observations were changed from work to distracting while retaining producer observations, the installed AX probe passed with elapsed 15 and aligned 0.
- The elapsed timer therefore continued advancing independently while explicit zero aligned evidence remained truthful.

## Unproven gates

- Missing producer data was not exercised in the installed UI before the cap.
- The required contrast between a genuinely absent producer and explicit zero producer evidence is therefore incomplete, even though explicit zero passed.
- The three public timing elements contained only aggregate timing and evidence wording, but a separate full accessibility-tree privacy scan for fixture app names and private values was not completed before the cap.

## Cleanup and isolation

- Fixture cleanup passed.
- A second `verify-clean` passed.
- QA private sentinel count was zero before runtime removal.
- QA LaunchAgent was absent after cleanup.
- Isolated QA app was absent after cleanup.
- Isolated QA runtime root was absent after cleanup.
- Production database contained zero `qa-zc024008-*` fixture rows.
- Canonical, tracker, registry, production app, and production runtime were not changed.

## Remaining rerun

One short signed session remains.

Use the same clean candidate and corrected fixture, reach the baseline card, remove all fixture producer observations, regenerate the Today snapshot, and verify the installed accessibility evidence explicitly reports that no Screenwatch time is available while elapsed remains present and aligned time is zero.

Then scan the open compact card accessibility subtree and prove that no fixture application names, task identifiers, window titles, URLs, or other private observation values are exposed.
