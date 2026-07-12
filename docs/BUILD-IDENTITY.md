# Build Identity

Every packaged Zoid Coach app records the exact Git commit and repository state in its copied `Info.plist` before signing.
The canonical identity is `zoid-coach-<40-character-commit>-<clean-or-dirty>`.

The package contains these keys:

- `ZoidCoachGitCommit`
- `ZoidCoachGitState`
- `ZoidCoachBuildIdentity`

`Scripts/verify-package.sh` rejects a package when any value is missing, malformed, or incoherent.
Scenario completion evidence must reference a clean build identity whose embedded commit equals the verified commit.
A dirty identity is useful for diagnosis but cannot prove scenario completion.
