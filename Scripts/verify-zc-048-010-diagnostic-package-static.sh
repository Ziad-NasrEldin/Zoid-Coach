#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

canonical="6dfb5886f4ca2d157745f10b5d737988a08d596a"
unexpected=""
while IFS= read -r path; do
  case "$path" in
    Scripts/verify-zc-048-010-diagnostic-package-static.sh | \
    Sources/ZoidCoachApp/DiagnosticExportPackagePresentation.swift | \
    Sources/ZoidCoachApp/Views/SettingsView.swift | \
    Sources/ZoidCoachInfrastructure/PrivacyDataService.swift | \
    Tests/ZoidCoachAppTests/DiagnosticExportPackagePresentationTests.swift | \
    Tests/ZoidCoachAppTests/PrivacyDataServiceTests.swift)
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
rg -F 'case "zoiddiagnostics":' Sources/ZoidCoachInfrastructure/PrivacyDataService.swift >/dev/null
rg -F 'let files = ["README.txt", "manifest.json", "counts.json"]' \
  Sources/ZoidCoachInfrastructure/PrivacyDataService.swift >/dev/null
rg -F 'Screenshots are excluded.' Sources/ZoidCoachInfrastructure/PrivacyDataService.swift >/dev/null
rg -F 'saveButtonTitle: "SAVE REVIEWED DIAGNOSTIC PACKAGE"' \
  Sources/ZoidCoachApp/DiagnosticExportPackagePresentation.swift >/dev/null
rg -F 'Button(DiagnosticExportPackagePresentation.preview.saveButtonTitle)' \
  Sources/ZoidCoachApp/Views/SettingsView.swift >/dev/null
rg -F 'DiagnosticExportPackagePresentation.preview.accessibilitySummary' \
  Sources/ZoidCoachApp/Views/SettingsView.swift >/dev/null
rg -F 'redactedDiagnosticPackageRejectsExistingAndUnsupportedDestinations' \
  Tests/ZoidCoachAppTests/PrivacyDataServiceTests.swift >/dev/null

if git diff --unified=0 "$canonical" -- | rg -n '^\+.*—' >/dev/null; then
  printf 'FAIL: ZC-048-010 diff contains an em dash.\n' >&2
  exit 1
fi

swiftc -parse \
  Sources/ZoidCoachApp/DiagnosticExportPackagePresentation.swift \
  Sources/ZoidCoachApp/Views/SettingsView.swift \
  Sources/ZoidCoachInfrastructure/PrivacyDataService.swift \
  Tests/ZoidCoachAppTests/DiagnosticExportPackagePresentationTests.swift \
  Tests/ZoidCoachAppTests/PrivacyDataServiceTests.swift

printf 'PASS: ZC-048-010 diagnostic package static verification\n'
