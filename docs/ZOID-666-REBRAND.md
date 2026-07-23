# Zoid 666 Rebrand Contract

## User-visible identity

The product name is Zoid 666.
The production app bundle is `Zoid 666.app` and the QA app bundle is `Zoid 666 QA.app`.
App menus, onboarding, Today, Settings, permission prompts, notifications, voice responses, Calendar artifacts, local fallback tasks, diagnostics, packaging output, and product documentation must use Zoid 666.

## Compatibility identities

The following identifiers intentionally retain `ZoidCoach` or `zoid-coach` because changing them would reset macOS permissions, disconnect the login agent, split Keychain data, break XPC trust, or invalidate existing scenario evidence:

- Swift package, module, target, type, and executable symbols such as `ZoidCoach`, `ZoidCoachAgent`, and `ZoidCoachStorage`.
- Production and QA bundle identifiers, signing identifiers, LaunchAgent labels, Mach service names, and plist filenames.
- Environment variable names beginning with `ZOID_COACH_`.
- Existing Keychain service identifiers.
- The `zoid-coach.sqlite` database filename, ownership markers, notification identifiers, build identities, scenario IDs, and documentation filenames referenced by audit tooling.

These compatibility identifiers are not presented as the product name in the end-user interface.

## Existing-user migration

On first launch, runtime storage moves from `Application Support/Zoid Coach` to `Application Support/Zoid 666` before any database consumer opens the product state.
The move is race-safe between the app and login agent and falls back to the legacy directory if macOS refuses the move, so rebranding cannot hide existing user data.
Database migration 27 rewrites persisted prompt summaries that contain the former product name.
Existing Zoid-owned Calendar storage is renamed from the former visible title to `Zoid 666` before it is reused.
The installer removes the former app-bundle path only after the newly signed `Zoid 666.app` has been copied and opened.

## Verification

The package verifier asserts both `CFBundleDisplayName` and `CFBundleName` against the production or QA identity manifest.
The runtime tests verify that the former Application Support directory is moved without changing its database bytes.
The migration tests verify that persisted prompt summaries are renamed and unrelated summaries remain unchanged.
A residue search may contain the former name only in migration inputs, legacy compatibility aliases, immutable historical evidence, and the backward-compatible spoken wake phrase.
