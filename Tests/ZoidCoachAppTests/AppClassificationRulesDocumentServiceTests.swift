import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test
func classificationRulesExportAndImportRoundTripWithoutOtherSettings() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-classification-rules-\(UUID().uuidString)", isDirectory: true)
    let destination = root.appendingPathComponent("rules.json")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let service = AppClassificationRulesDocumentService()
    let policy = BehaviorPolicy(
        workApplications: ["Xcode"],
        gamingApplications: ["Steam"],
        communicationApplications: ["Slack"]
    )

    let exported = try service.export(policy, to: destination)
    let imported = try service.importRules(from: destination)

    #expect(imported == policy)
    #expect(exported.workCount == 1)
    #expect(exported.communicationCount == 1)
    #expect(exported.gamingCount == 1)
    let text = try String(contentsOf: destination, encoding: .utf8)
    #expect(text.contains(#""schemaVersion" : 1"#))
    #expect(!text.localizedCaseInsensitiveContains("timeZone"))
    #expect(!text.localizedCaseInsensitiveContains("api"))
}

@Test
func classificationRulesImportRejectsConflictsBlanksAndDuplicates() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-classification-rules-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let service = AppClassificationRulesDocumentService()

    for (name, json) in [
        ("conflict", #"{"schemaVersion":1,"workApplications":["Slack"],"communicationApplications":[" slack "],"gamingApplications":[]}"#),
        ("blank", #"{"schemaVersion":1,"workApplications":[""],"communicationApplications":[],"gamingApplications":[]}"#),
        ("duplicate", #"{"schemaVersion":1,"workApplications":["Xcode"," xcode "],"communicationApplications":[],"gamingApplications":[]}"#),
    ] {
        let url = root.appendingPathComponent("\(name).json")
        try Data(json.utf8).write(to: url)
        #expect(throws: AppClassificationRulesDocumentError.self) {
            try service.importRules(from: url)
        }
    }
}

@Test
func classificationRulesImportRejectsSymlinksOversizedFilesAndUnknownSchemas() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-classification-rules-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let service = AppClassificationRulesDocumentService(maximumImportBytes: 128)
    let valid = root.appendingPathComponent("valid.json")
    let link = root.appendingPathComponent("link.json")
    let oversized = root.appendingPathComponent("oversized.json")
    let future = root.appendingPathComponent("future.json")
    try Data(#"{"schemaVersion":1,"workApplications":[],"communicationApplications":[],"gamingApplications":[]}"#.utf8).write(to: valid)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
    try Data(repeating: 65, count: 256).write(to: oversized)
    try Data(#"{"schemaVersion":99,"workApplications":[],"communicationApplications":[],"gamingApplications":[]}"#.utf8).write(to: future)

    #expect(throws: AppClassificationRulesDocumentError.self) { try service.importRules(from: link) }
    #expect(throws: AppClassificationRulesDocumentError.self) { try service.importRules(from: oversized) }
    #expect(throws: AppClassificationRulesDocumentError.self) { try service.importRules(from: future) }
}

@Test
func classificationRulesExportRefusesSymlinkDestination() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-classification-rules-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let original = root.appendingPathComponent("original.json")
    let link = root.appendingPathComponent("link.json")
    try Data("preserve".utf8).write(to: original)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)

    #expect(throws: AppClassificationRulesDocumentError.self) {
        try AppClassificationRulesDocumentService().export(BehaviorPolicy(), to: link)
    }
    #expect(try String(contentsOf: original, encoding: .utf8) == "preserve")
}
