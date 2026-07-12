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
- Full logs are preserved under `.audit/runs/app-classification-management/candidate/logs/`.

## Four-worker full-suite caveat

- `swift test --parallel --num-workers 4` started the repository-wide suite but the SwiftPM testing helper became idle for more than four minutes with no worker processes or CPU use.
- The preserved process sample shows the helper waiting in the main run loop after starting tests.
- The attempt was terminated rather than misreported as a pass, and the full suite then passed serially.
- Focused affected suites did pass with exactly four workers.

## Independent acceptance still required

- A fresh verifier must use the clean signed-QA package to search, individually classify, bulk classify a filtered set, save, relaunch, export, inspect the JSON, import a replacement, save, relaunch, and reset.
- The root integrator owns tracker and registry changes after visible proof.
