# Deterministic fixture verification commands

## Identity

```sh
pwd
git branch --show-current
git rev-parse HEAD
git status --short --branch
```

Result:

```text
/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/foundation-reverify
codex/zc-foundation-reverify
515016a5e9cba03b0a2bada9f63066c99c26cd39
## codex/zc-foundation-reverify
```

## Clean focused rebuild

```sh
swift package clean
swift test --filter DeterministicTestControl
swift test --skip-build --filter DeterministicTestControl --quiet
```

Result:

```text
Test run with 9 tests passed.
```

## Independent adversarial probe

A temporary Swift Testing file was added to the existing test target and removed after the run.

It used only unique temporary directories and synthetic marker content.

```sh
swift test --filter independentProbe
swift test --skip-build --filter independentProbe --quiet
```

Result:

```text
Test run with 7 tests passed.
```

The probe independently covered:

- Protected-root ancestor and descendant overlap.
- Actual production-root protection when extra protected roots are supplied.
- Parent and final fixture symlinks.
- Nonexistent child hierarchies.
- Traversal, separators, empty, overlength, Unicode, and uppercase identifiers.
- Repeat preparation and stale-state reset.
- Sibling-preserving cleanup.
- Cleanup after final-path symlink replacement.

## Full suite

```sh
swift test
swift test --skip-build --quiet
```

Result:

```text
Test run with 202 tests in 4 suites passed after 0.901 seconds.
```

## Clean release build

```sh
swift package clean
swift build -c release --quiet
```

Result: exit code 0.

The output summarizer printed source-code occurrences of the words `error` and `warnings` from an AVFoundation conversion call, but the Swift command itself exited successfully.

No production service or data verification command was run because this task prohibited touching production data or services.
