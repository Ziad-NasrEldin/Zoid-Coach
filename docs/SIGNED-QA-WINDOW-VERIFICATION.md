# Signed QA window verification

## Diagnosis

The reported signed QA empty window was a false positive caused by an invalid visibility oracle.
On the same signed process and 1180 by 760 window, System Events returned zero items for `count of entire contents`, while the native macOS Accessibility API exposed 42 content nodes and activated the onboarding continuation.
A pixel capture of that same window showed the complete Setup 2 of 12 interface.
The later disappearance was independent and intentional because a `--background-schedule` launch hides the application after two seconds.

## Verifier guidance

Do not use System Events `count of entire contents` to decide whether a SwiftUI window is empty or usable.
System Events can return zero for a fully rendered and natively accessible SwiftUI hierarchy.
Use `Scripts/verify-signed-qa-window-content.sh` for native Accessibility traversal, actionable control verification, and optional pixel evidence.
Use `Scripts/verify-signed-qa-launch-visibility.sh` to prove that a foreground launch remains visible and a `--background-schedule` launch hides intentionally.

## Commands

Run the installed signed lifecycle with an optional screenshot path:

```sh
Scripts/verify-signed-qa-window-content.sh <package-repository> <isolated-qa-root> <isolated-install-root> [screenshot-path]
```

Run the foreground and background launch regression with an optional evidence directory:

```sh
Scripts/verify-signed-qa-launch-visibility.sh <package-repository> <isolated-qa-root> [evidence-directory]
```
