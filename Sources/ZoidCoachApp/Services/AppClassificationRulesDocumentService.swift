import Foundation
import ZoidCoachCore

struct AppClassificationRulesExportReceipt: Equatable, Sendable {
    let workCount: Int
    let communicationCount: Int
    let gamingCount: Int
}

struct AppClassificationRulesDocumentService: Sendable {
    let maximumImportBytes: Int

    init(maximumImportBytes: Int = 1_048_576) {
        self.maximumImportBytes = maximumImportBytes
    }

    func export(
        _ policy: BehaviorPolicy,
        to destination: URL
    ) throws -> AppClassificationRulesExportReceipt {
        guard destination.pathExtension.lowercased() == "json" else {
            throw AppClassificationRulesDocumentError.invalidFileType
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory != true else {
                throw AppClassificationRulesDocumentError.unsafeFile
            }
        }
        let document = AppClassificationRulesDocument(policy: policy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: destination, options: [.atomic])
        return AppClassificationRulesExportReceipt(
            workCount: policy.workApplications.count,
            communicationCount: policy.communicationApplications.count,
            gamingCount: policy.gamingApplications.count
        )
    }

    func importRules(from source: URL) throws -> BehaviorPolicy {
        guard source.pathExtension.lowercased() == "json" else {
            throw AppClassificationRulesDocumentError.invalidFileType
        }
        let values = try source.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AppClassificationRulesDocumentError.unsafeFile
        }
        guard let size = values.fileSize, size <= maximumImportBytes else {
            throw AppClassificationRulesDocumentError.fileTooLarge
        }
        let data = try Data(contentsOf: source, options: [.mappedIfSafe])
        let document: AppClassificationRulesDocument
        do {
            document = try JSONDecoder().decode(AppClassificationRulesDocument.self, from: data)
        } catch {
            throw AppClassificationRulesDocumentError.invalidDocument
        }
        guard document.schemaVersion == AppClassificationRulesDocument.currentSchemaVersion else {
            throw AppClassificationRulesDocumentError.unsupportedSchema(document.schemaVersion)
        }
        try Self.validate(document)
        return BehaviorPolicy(
            workApplications: document.workApplications,
            gamingApplications: document.gamingApplications,
            communicationApplications: document.communicationApplications
        )
    }

    private static func validate(_ document: AppClassificationRulesDocument) throws {
        let groups = [
            document.workApplications,
            document.communicationApplications,
            document.gamingApplications,
        ]
        var all = Set<String>()
        for group in groups {
            let normalized = group.map(BehaviorPolicy.normalize)
            guard normalized.allSatisfy({ !$0.isEmpty }) else {
                throw AppClassificationRulesDocumentError.blankApplication
            }
            guard Set(normalized).count == normalized.count else {
                throw AppClassificationRulesDocumentError.duplicateApplication
            }
            guard all.isDisjoint(with: normalized) else {
                throw AppClassificationRulesDocumentError.conflictingApplication
            }
            all.formUnion(normalized)
        }
    }
}

private struct AppClassificationRulesDocument: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let workApplications: [String]
    let communicationApplications: [String]
    let gamingApplications: [String]

    init(policy: BehaviorPolicy) {
        schemaVersion = Self.currentSchemaVersion
        workApplications = policy.workApplications
        communicationApplications = policy.communicationApplications
        gamingApplications = policy.gamingApplications
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workApplications
        case communicationApplications
        case gamingApplications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        workApplications = try container.decodeIfPresent([String].self, forKey: .workApplications) ?? []
        communicationApplications = try container.decodeIfPresent([String].self, forKey: .communicationApplications) ?? []
        gamingApplications = try container.decodeIfPresent([String].self, forKey: .gamingApplications) ?? []
    }
}

enum AppClassificationRulesDocumentError: LocalizedError, Equatable {
    case invalidFileType
    case unsafeFile
    case fileTooLarge
    case invalidDocument
    case unsupportedSchema(Int)
    case blankApplication
    case duplicateApplication
    case conflictingApplication

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            "Choose a JSON classification-rules file."
        case .unsafeFile:
            "Classification rules cannot be read from or written through a folder or symbolic link."
        case .fileTooLarge:
            "The classification-rules file is larger than 1 MB."
        case .invalidDocument:
            "The file is not a valid Zoid 666 classification-rules document."
        case let .unsupportedSchema(version):
            "Classification-rules schema \(version) is not supported."
        case .blankApplication:
            "A classification rule contains a blank application name."
        case .duplicateApplication:
            "An application appears more than once in one classification."
        case .conflictingApplication:
            "An application appears in more than one classification."
        }
    }
}
