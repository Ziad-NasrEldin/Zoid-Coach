# Sanitized command record

All commands ran in the dedicated `proof-reverify` worktree at target commit `fde4f3f0b7b83ea561a02e879c407edff489506b`.

No command launched or installed the app.

No command accessed a production service or production data.

```bash
git status --short --branch
git rev-parse HEAD
python3 Scripts/scenario_registry.py validate
python3 -m unittest discover -s Tests/ScenarioRegistryTests -v
npx -y ajv-cli@5.0.0 validate --spec=draft2020 -s docs/scenario-registry.schema.json -d docs/scenario-registry.json --strict=true
python3 <registry-count-and-disposition-audit>
python3 <schema-and-manual-contract-set-comparison>
python3 <schema-valid-status-mutation-versus-manual-validator-reproduction>
python3 <scenario-evidence-parent-symlink-containment-reproduction>
python3 <scenario-evidence-null-assertion-reproduction>
python3 <foreign-git-environment-evidence-binding-reproduction>
python3 <foreign-git-environment-build-stamp-reproduction>
swift test
swift test --filter extraProtectedRootsCannotReplaceRealProductionRoots
swift test --filter AppBuildIdentityTests
swift build --configuration release
CONFIGURATION=release Scripts/package-app.sh
Scripts/verify-package.sh ".build/app/Zoid Coach.app" --expected-commit fde4f3f0b7b83ea561a02e879c407edff489506b --require-clean
Scripts/verify-package.sh ".build/app/Zoid Coach.app" --expected-commit 0000000000000000000000000000000000000000 --require-clean
Scripts/verify-build-identity.sh <temporary-dirty-plist> --expected-commit fde4f3f0b7b83ea561a02e879c407edff489506b --require-clean
plutil -extract CFBundleIdentifier raw -o - ".build/app/Zoid Coach.app/Contents/Info.plist"
plutil -extract ZoidCoachGitCommit raw -o - ".build/app/Zoid Coach.app/Contents/Info.plist"
plutil -extract ZoidCoachGitState raw -o - ".build/app/Zoid Coach.app/Contents/Info.plist"
plutil -extract ZoidCoachBuildIdentity raw -o - ".build/app/Zoid Coach.app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 ".build/app/Zoid Coach.app"
codesign -d --verbose=4 ".build/app/Zoid Coach.app/Contents/MacOS/ZoidCoach"
codesign -d --verbose=4 ".build/app/Zoid Coach.app/Contents/MacOS/ZoidCoachAgent"
strings ".build/app/Zoid Coach.app/Contents/MacOS/ZoidCoach" | rg "settings\.buildIdentity|Build identity"
shasum -a 256 <audited-source-and-package-artifacts>
```
