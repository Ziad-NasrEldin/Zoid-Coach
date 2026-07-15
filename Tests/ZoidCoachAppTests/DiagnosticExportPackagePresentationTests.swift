import Testing
@testable import ZoidCoachApp

@Test
func diagnosticExportPackagePreviewNamesEveryArtifactAndPrivacyExclusion() {
    let preview = DiagnosticExportPackagePresentation.preview

    #expect(preview.packageExtension == "zoiddiagnostics")
    #expect(preview.artifacts.map(\.fileName) == ["README.txt", "manifest.json", "counts.json"])
    #expect(preview.exclusions == [
        "Task and event titles",
        "Conversation text",
        "URLs and file paths",
        "Screenshots",
        "Request payloads",
        "Credentials",
    ])
    #expect(preview.accessibilitySummary.contains("3 files"))
    #expect(preview.accessibilitySummary.contains("Credentials"))
}

@Test
func diagnosticExportPackageSettingsCopyRequiresReviewBeforeSaving() {
    let preview = DiagnosticExportPackagePresentation.preview

    #expect(preview.saveButtonTitle == "SAVE REVIEWED DIAGNOSTIC PACKAGE")
    #expect(preview.panelTitle == "Save reviewed Zoid 666 diagnostic package")
    #expect(preview.panelPrompt == "SAVE DIAGNOSTIC PACKAGE")
    #expect(preview.suggestedFileName == "Zoid 666 Support.zoiddiagnostics")
    #expect(preview.suggestedFileName.hasSuffix(".\(preview.packageExtension)"))
}
