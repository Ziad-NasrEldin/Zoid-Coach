# App-classification Management Acceptance Evidence

## Scenario scope

- `ZC-045-008` - Review application rules.
- `ZC-045-013` - Import classification rules.
- `ZC-045-014` - Export classification rules.
- `ZC-025-001` - See known work applications classified according to configured rules.
- `ZC-025-002` - See known games classified as gaming.

## Implemented end-user behavior

- Settings discovers installed, observed, and previously saved applications and supports search plus All, Auto, Work, Communication, and Gaming filters.
- Every row can be assigned individually.
- The currently filtered result can be bulk-assigned only after a confirmation that states the affected count and category.
- Every explicit rule can be returned to Automatic only after a destructive confirmation.
- Communication stays visibly distinct in the rule ledger and explicitly counts as work in runtime classification.
- Import opens a native JSON chooser, validates the complete document before mutation, previews category counts, and requires replacement confirmation.
- Export opens a native JSON destination chooser and atomically writes only schema version and normalized app-rule arrays.
- Import rejects wrong extensions, non-regular files, symbolic links, inputs over 1 MB, malformed JSON, unknown schemas, blanks, duplicates, and cross-category conflicts.
- Import, bulk edits, and reset change only the Settings draft and explicitly require Save Settings, preserving the existing versioned conflict-recovery flow.
- Stable accessibility identifiers cover bulk category actions, import, export, reset, and result notices.

## Automated proof

- Focused four-worker command passed policy, Settings draft, Today runtime, and document-service tests.
- Authoritative serial `swift test` passed 476 tests across 5 suites in 23.451 seconds.
- `swift build -c release` passed.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests -p "test_*.py"` passed 41 tests.
- Clean signed-QA packaging passed package, LaunchAgent, Mach-service, signing-identity, embedded clean-build-identity, and designated-requirement checks with isolated run root `/tmp/zoid-666-app-classification`.
- Full logs are preserved under `.audit/runs/app-classification-management/candidate/logs/`.

## Four-worker full-suite caveat

- `swift test --parallel --num-workers 4` started the repository-wide suite but the SwiftPM testing helper became idle for more than four minutes with no worker processes or CPU use.
- The preserved process sample shows the helper waiting in the main run loop after starting tests.
- The attempt was terminated rather than misreported as a pass, and the full suite then passed serially.
- Focused affected suites did pass with exactly four workers.

## Independent acceptance still required

- A fresh verifier must use the clean signed-QA package to search, individually classify, bulk classify a filtered set, save, relaunch, export, inspect the JSON, import a replacement, save, relaunch, and reset.
- The root integrator owns tracker and registry changes after visible proof.

## Independent verifier pass

- Verification branch `codex/verify-app-classification` reproduced the exact 53-test affected set with four workers.
- All 53 affected tests passed.
- All 41 Python registry and evidence tests passed, and the registry validated exactly 666 scenarios with no tracker drift.
- The release build passed independently.
- A clean scratch-path full serial test run compiled successfully but the SwiftPM testing helper became idle while three other repository-wide test helpers were concurrently active in sibling worktrees.
- The verifier stopped only its own idle helper and did not count that attempt as a pass.
- The candidate's preserved authoritative serial run remains the current 476-test full-suite proof until an uncontended post-integration run replaces it.

## Visible signed-QA evidence

- The signed-QA Settings surface visibly loaded 131 installed, observed, and saved applications.
- Searching for `Discord` reduced the ledger to exactly one result.
- The verifier individually assigned Discord to Communication and confirmed the visible distinct selection.
- The verifier bulk-assigned the filtered result to Gaming only after the confirmation stated the exact one-app count and draft-only behavior.
- Export created `zoid-666-app-classification-verifier.json` with only `schemaVersion`, `workApplications`, `communicationApplications`, and `gamingApplications`.
- The exported document normalized Discord to `discord` and contained no unrelated settings or secrets.
- Import reviewed `verification-import.json`, previewed one Work, one Communication, and one Gaming rule, and required explicit replacement confirmation before mutating the draft.
- The imported draft visibly returned Discord to the distinct Communication category.
- Reset presented an explicit destructive confirmation explaining that every Work, Communication, and Gaming rule would return to Automatic and remain a draft until Save Settings.

## Remaining installed-runtime gate

- The directly launched candidate bundle had no installed QA policy database and correctly exposed `Policy storage is unavailable. Settings are read-only until local storage recovers.`
- That environment could prove the complete draft interaction, import, export, and reset surfaces but could not prove Save Settings or relaunch persistence.
- A root-controlled signed-runtime installation is still required after the existing offline-work package lock is released.
- ScreenCaptureKit also returned `SCStreamErrorDomain -3811` after the reset confirmation, so the post-reset frame was not claimed as proof.
