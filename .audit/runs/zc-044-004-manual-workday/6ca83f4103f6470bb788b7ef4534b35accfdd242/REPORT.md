# ZC-044-004 manual workday signed acceptance

## Verdict

ZC-044-004 is fully implemented and usable end to end at signed verifier tip `243a3d8d6f98da29c84bf4fe25d722ad4c26f62f`.
The final evidence source is `/private/tmp/zc044004-243a-evidence`.
The run completed the normal Settings, Start, End, stale-action, relaunch, privacy, restoration, and uninstall journey against one exact installed identity.

## Signed identity and runtime binding

- The preflight self-test passed.
- The signed package contained exact build commit `243a3d8d6f98da29c84bf4fe25d722ad4c26f62f`.
- The verified clean build identity was `zoid-coach-243a3d8d6f98da29c84bf4fe25d722ad4c26f62f-clean`.
- The foreground application was bound before helper registration.
- The bound application PID, helper PID, installed executables, and isolated database matched the same signed package and QA root.
- The supported post-onboarding ready state exposed the normal Today window.

The binding evidence is in `preflight-self-test.txt`, `preflight-foreground-unregistered.txt`, `preflight-foreground-bound.txt`, `preflight-prepared.txt`, and `window-today.txt` under the external evidence source.

## Completed end-user journey

- Settings visibly selected manual workday mode.
- Manual mode and its disabled fixed-hour semantics persisted after save and relaunch.
- A ready task visibly exposed Start Workday.
- Start created the expected active task and open interval.
- A stale Start action was rejected without changing the active state.
- The active task visibly exposed confirmed End Workday.
- A stale End action was rejected without changing the active state.
- Confirmed End closed the interval and produced the ended state.
- The ended state persisted through an ordinary relaunch.
- Invalid Start and End controls remained omitted outside their valid lifecycle states.

The visible evidence is in `settings-select-manual.txt`, `settings-persisted.txt`, `ready-visible-confirmed-start.txt`, `stale-start.txt`, `active-visible-confirmed-end.txt`, `stale-end.txt`, `ended-before-relaunch.txt`, and `ended-relaunch-passed.png`.

## Privacy, restoration, and cleanup

- The strict relaunch accessibility scan passed without exposing the seeded private selection reason, task identity, notes, database path, or QA root.
- The namespaced fixture restored the original policy and removed every fixture-owned row.
- Final database proof passed.
- The isolated signed QA runtime uninstalled successfully.
- Production process state was unchanged.

The cleanup evidence is in `ended-relaunch-strict-privacy.txt`, `fixture-cleanup.txt`, `final-cleanup-proof.txt`, `final-db-proof.txt`, `uninstall.txt`, and `production-processes-diff.txt`.

## Tracker decision

Every required installed-app and UI-automation proof class now passes against the same signed identity.
The previous launch-order blocker is resolved, so the scenario qualifies as Fully implemented.
