#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

canonical="6dfb5886f4ca2d157745f10b5d737988a08d596a"
unexpected=""
while IFS= read -r path; do
  case "$path" in
    Scripts/verify-zc-048-010-diagnostic-package-static.sh | \
    Scripts/qa-zc048010-diagnostic-package-ax-probe.swift | \
    Scripts/qa-zc048010-diagnostic-package-fixture.sh | \
    Scripts/qa-zc048010-signed-preflight.sh | \
    Sources/ZoidCoachApp/DiagnosticExportPackagePresentation.swift | \
    Sources/ZoidCoachApp/Views/SettingsView.swift | \
    Sources/ZoidCoachInfrastructure/PrivacyDataService.swift | \
    Tests/ZoidCoachAppTests/DiagnosticExportPackagePresentationTests.swift | \
    Tests/ZoidCoachAppTests/PrivacyDataServiceTests.swift | \
    docs/ZC-048-010-SIGNED-QA-RUNBOOK.md)
      ;;
    *)
      unexpected+="${unexpected:+$'\n'}$path"
      ;;
  esac
done < <(
  {
    git diff --name-only "$canonical" --
    git ls-files --others --exclude-standard
  } | sort -u
)
if [[ -n "$unexpected" ]]; then
  printf 'FAIL: ZC-048-010 changed files outside ownership:\n%s\n' "$unexpected" >&2
  exit 1
fi

rg -F 'artifacts.map(\.fileName) == ["README.txt", "manifest.json", "counts.json"]' \
  Tests/ZoidCoachAppTests/DiagnosticExportPackagePresentationTests.swift >/dev/null
rg -F 'public enum PrivacyDiagnosticPackageContract' \
  Sources/ZoidCoachInfrastructure/PrivacyDataService.swift >/dev/null
rg -F '"files": PrivacyDiagnosticPackageContract.fileNames' \
  Sources/ZoidCoachInfrastructure/PrivacyDataService.swift >/dev/null
rg -F 'exclusions: PrivacyDiagnosticPackageContract.exclusions' \
  Sources/ZoidCoachApp/DiagnosticExportPackagePresentation.swift >/dev/null
rg -F 'Screenshots are excluded.' Sources/ZoidCoachInfrastructure/PrivacyDataService.swift >/dev/null
rg -F 'saveButtonTitle: "SAVE REVIEWED DIAGNOSTIC PACKAGE"' \
  Sources/ZoidCoachApp/DiagnosticExportPackagePresentation.swift >/dev/null
rg -F 'Button(DiagnosticExportPackagePresentation.preview.saveButtonTitle)' \
  Sources/ZoidCoachApp/Views/SettingsView.swift >/dev/null
rg -F 'DiagnosticExportPackagePresentation.preview.accessibilitySummary' \
  Sources/ZoidCoachApp/Views/SettingsView.swift >/dev/null
rg -F 'redactedDiagnosticPackageRejectsExistingAndUnsupportedDestinations' \
  Tests/ZoidCoachAppTests/PrivacyDataServiceTests.swift >/dev/null
rg -F 'try FileManager.default.createSymbolicLink' \
  Tests/ZoidCoachAppTests/PrivacyDataServiceTests.swift >/dev/null
rg -F 'values = try candidate.resourceValues' \
  Sources/ZoidCoachInfrastructure/PrivacyDataService.swift >/dev/null
rg -F 'swift "$PROBE" --pid "$PID" --phase existing --destination "$EXISTING_PACKAGE"' \
  docs/ZC-048-010-SIGNED-QA-RUNBOOK.md >/dev/null
rg -F 'swift "$PROBE" --pid "$PID" --phase finder --destination "$RETRY_PACKAGE"' \
  docs/ZC-048-010-SIGNED-QA-RUNBOOK.md >/dev/null
rg -F 'open "$APP" --args --qa-open-main' \
  docs/ZC-048-010-SIGNED-QA-RUNBOOK.md >/dev/null
rg -F -- '--require-qa-open-main --require-helper-unregistered' \
  docs/ZC-048-010-SIGNED-QA-RUNBOOK.md >/dev/null
rg -F -- '--wait-for-foreground-database' \
  docs/ZC-048-010-SIGNED-QA-RUNBOOK.md >/dev/null
rg -F 'READINESS_TEST_CASE="delayed-success"' \
  Scripts/qa-zc048010-signed-preflight.sh >/dev/null
rg -F 'READINESS_TEST_CASE="never-appears"' \
  Scripts/qa-zc048010-signed-preflight.sh >/dev/null
rg -F 'READINESS_TEST_CASE="pid-exit"' \
  Scripts/qa-zc048010-signed-preflight.sh >/dev/null
rg -F 'wrong database root was accepted' \
  Scripts/qa-zc048010-signed-preflight.sh >/dev/null
rg -F -- '--require-qa-open-main --expected-app-pid "$PID"' \
  docs/ZC-048-010-SIGNED-QA-RUNBOOK.md >/dev/null
rg -F '! has_argument "$APP_COMMAND" "--background-schedule"' \
  Scripts/qa-zc048010-signed-preflight.sh >/dev/null

if git diff --unified=0 "$canonical" -- | rg -n '^\+.*\x{2014}' >/dev/null; then
  printf 'FAIL: ZC-048-010 diff contains an em dash.\n' >&2
  exit 1
fi

swiftc -parse \
  Sources/ZoidCoachApp/DiagnosticExportPackagePresentation.swift \
  Sources/ZoidCoachApp/Views/SettingsView.swift \
  Sources/ZoidCoachInfrastructure/PrivacyDataService.swift \
  Tests/ZoidCoachAppTests/DiagnosticExportPackagePresentationTests.swift \
  Tests/ZoidCoachAppTests/PrivacyDataServiceTests.swift
swiftc -typecheck Scripts/qa-zc048010-diagnostic-package-ax-probe.swift
zsh -n Scripts/qa-zc048010-diagnostic-package-fixture.sh
zsh -n -c 'source Scripts/qa-zc048010-signed-preflight.sh'
Scripts/qa-zc048010-signed-preflight.sh --self-test >/dev/null

printf 'PASS: ZC-048-010 diagnostic package static verification\n'
