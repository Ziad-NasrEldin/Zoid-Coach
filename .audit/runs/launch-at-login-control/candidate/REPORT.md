# Launch at login control candidate

## Scope

This candidate owns `ZC-044-001`.
It makes the existing Background Agent window expose the user's launch-at-login choice independently from helper runtime health.

## End-user behavior

- The window shows a dedicated Launch at Login state as Enabled, Disabled, Waiting for Approval, Unavailable, or Unknown.
- An enabled helper with a missing or stale heartbeat can still be disabled.
- A registration waiting for macOS approval can be disabled without forcing the user to approve it first.
- Enable and disable actions now name Launch at Login explicitly.
- Disable confirmation explains that automatic background work stops while local plans, reviews, and history remain on the Mac.
- Runtime heartbeat health remains separate, so an enabled registration is never misrepresented as a running helper.

## Focused proof

- `swift test --filter "AgentLifecycleController|AgentLaunchService"` passed 14 tests.
- The exact stale-heartbeat journey proves the registration remains Enabled, Disable unregisters it, and the UI state becomes Disabled.
- Existing QA isolation, packaged-QA enable and disable, forced repair, Login Items recovery, read-only heartbeat, and fingerprint tests still pass.
- `swift build -c release` passed.
- `git diff --check` passed.
- QA packaging passed package, LaunchAgent, Mach service, signing-identity, on-disk signature, and designated-requirement validation.
- The packaged artifact is `.build/app-qa/Zoid 666 QA.app` inside the isolated worktree.

## Verifier handoff

A fresh verifier should rebase or cherry-pick this candidate onto the current integration tip and rerun the 14 focused tests plus a release build.
Using the serialized signed-QA runtime, open Background Agent and first confirm Launch at Login reports Enabled while a fresh heartbeat reports the helper running.
Stop the helper or age the canonical heartbeat until runtime health becomes Attention, then confirm Disable Launch at Login remains available.
Choose Disable Launch at Login, accept the confirmation, and verify the visible state becomes Disabled, the helper registration is removed, and existing local plans, reviews, and history remain unchanged.
Relaunch the foreground app and verify the state remains Disabled without silently re-registering the helper.
Choose Enable Launch at Login, complete macOS approval if requested, and verify the state becomes Enabled and a fresh heartbeat returns runtime health to Healthy.
The verifier owns installed-app evidence and any tracker, registry, or Lavish update.
The shared runtime and root worktree remain untouched by this candidate.
