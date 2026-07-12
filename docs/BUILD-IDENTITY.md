# Build Identity

Every packaged Zoid 666 app records the exact Git commit and repository state in its copied `Info.plist` before signing.
The canonical identity is `zoid-coach-<40-character-commit>-<clean-or-dirty>`.

The package contains these keys:

- `ZoidCoachGitCommit`
- `ZoidCoachGitState`
- `ZoidCoachBuildIdentity`

Settings displays the short commit and state, while its accessibility label and help text expose the exact identity.
`Scripts/verify-package.sh` rejects a package when any value is missing, malformed, incoherent, or different from an expected commit.
Verifiers pass `--require-clean` when the package is intended to prove scenario completion.
Scenario completion evidence must reference a clean build identity whose embedded commit equals the verified commit.
A dirty identity is useful for diagnosis but cannot prove scenario completion.
