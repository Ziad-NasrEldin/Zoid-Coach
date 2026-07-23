# Weekly causal-evidence verifier report

## Verdict

The corrected candidate at `b7665f2aec2551bd7b518edfeee12c8337e75dc7` is implemented progress, with signed relaunch persistence still remaining.
The tracker may advance only from `Not implemented` to `Touches remaining`.

## Source and focused tests

- The candidate changes only `WeeklyReviewView.swift`, `WeeklyReviewPatternPresentation.swift`, and `WeeklyReviewPatternPresentationTests.swift` relative to canonical base `16a94762e7f990dbfec2dcf09eb1b33070dc4194`.
- The focused Swift Testing filter ran all seven presentation tests and all six existing weekly-review store tests.
- Result: `Test run with 13 tests in 0 suites passed after 0.219 seconds.`
- The focused tests cover hypothesis, confidence, observed evidence, alternative explanation, the not-proven-cause boundary, collapsed accessibility privacy, constrained-width wrapping, and derivation from persisted weekly evidence.

## Signed installed-app proof

- `Scripts/install-signed-qa-runtime.sh` packaged and installed the exact candidate as `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app`.
- Package signing, designated-requirement validation, QA XPC writability, prompt timeline availability, and the QA LaunchAgent heartbeat passed.
- A deterministic prior-week fixture provided seven confirmed review days, 21 observations, and repeated blocked events for a task titled `Private launch contract`.
- In the collapsed blocked-pattern card, the accessibility summary included the hypothesis, sample count, confidence, and not-proven-cause caveat, but did not expose the hidden private task title.
- The verifier focused `reviews.weekly.pattern.2026-07-04-blockedTasks.evidence` and activated it with a real Space key event through `weekly-ax-driver.swift`.
- The expanded installed-app accessibility tree exposed `Private launch contract: 2 blocked events`, the alternative explanation, and `NOT PROVEN CAUSE`.
- A second real Space key event collapsed the same control, restored `SHOW EVIDENCE`, and removed the private task title from the collapsed accessibility tree.
- The installed window was narrowed to 720 by 760 points while the candidate's constrained-width hosted test independently proved that the long hypothesis, evidence, alternative, and caveat text remains fully laid out.

## Remaining acceptance work

- The required app and helper relaunch against unchanged persisted rows was not completed before the signed-runtime time cap.
- The runtime was uninstalled and the isolated QA data root was removed after the cap.
- Do not mark the causal-evidence scenario fully implemented until a fresh signed run proves that the same pattern and disclosure boundaries are derived after both the app and helper relaunch.

## Isolation

- The signed QA runtime and QA roots were removed successfully.
- No canonical dirty files were modified during signed verification.
