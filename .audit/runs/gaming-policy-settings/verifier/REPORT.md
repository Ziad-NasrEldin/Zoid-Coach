# Gaming Policy Settings Verification

## Code result

The candidate correctly adds five-minute stepper controls for the stored daily base allowance and one-time priority-completion reward.
The accepted range matches policy validation from 0 through 1,440 minutes.
Draft reconstruction, conflict-safe merge, explicit overlapping reapply, and runtime `GamingStatusCalculator` semantics are covered by focused tests.
Copy remains factual and non-punitive.

## Proof

- `swift test --filter SettingsPolicyDraftTests` passed.
- One release build passed.
- `git diff --check` passed.

## Signed acceptance boundary

Two isolated signed-install attempts exited without creating an installed app or registering the QA helper and produced no diagnostic output.
The branch remained clean and neither attempt mutated the shared runtime.
Per the verifier timebox, no further package retry was performed.

Stepper editing, save through the live agent, relaunch persistence, and the Today allowance/reward effect remain unverified in an installed app.
The mapped tracker scenarios therefore remain conservative.

The candidate configures a fixed reward for completion of the existing priority objective.
It does not let the user choose an arbitrary set of unlock tasks, so `ZC-029-003` remains only partially implemented.
