import Foundation

struct DiagnosticExportPackageArtifact: Equatable, Sendable, Identifiable {
    let fileName: String
    let detail: String

    var id: String { fileName }
}

struct DiagnosticExportPackagePresentation: Equatable, Sendable {
    let packageExtension: String
    let saveButtonTitle: String
    let panelTitle: String
    let panelPrompt: String
    let suggestedFileName: String
    let artifacts: [DiagnosticExportPackageArtifact]
    let exclusions: [String]

    static let preview = DiagnosticExportPackagePresentation(
        packageExtension: "zoiddiagnostics",
        saveButtonTitle: "SAVE REVIEWED DIAGNOSTIC PACKAGE",
        panelTitle: "Save reviewed Zoid 666 diagnostic package",
        panelPrompt: "SAVE DIAGNOSTIC PACKAGE",
        suggestedFileName: "Zoid 666 Support.zoiddiagnostics",
        artifacts: [
            .init(fileName: "README.txt", detail: "Plain-language contents and privacy boundaries."),
            .init(fileName: "manifest.json", detail: "Package format, creation time, and the complete file list."),
            .init(fileName: "counts.json", detail: "Schema version and grouped status counts for actions, sources, prompts, and meeting suggestions."),
        ],
        exclusions: [
            "Task and event titles",
            "Conversation text",
            "URLs and file paths",
            "Screenshots",
            "Request payloads",
            "Credentials",
        ]
    )

    var accessibilitySummary: String {
        let fileSummary = artifacts.map { "\($0.fileName), \($0.detail)" }.joined(separator: " ")
        return "Diagnostic package preview. \(artifacts.count) files. \(fileSummary) Excluded: \(exclusions.joined(separator: ", "))."
    }
}
