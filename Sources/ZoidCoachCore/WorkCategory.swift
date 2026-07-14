import Foundation

public enum WorkCategory: String, CaseIterable, Codable, Sendable {
    case deepWork = "deep_work"
    case creativeWork = "creative_work"
    case research
    case communication
    case administration
    case uncategorized

    public var title: String {
        switch self {
        case .deepWork: "Deep work"
        case .creativeWork: "Creative work"
        case .research: "Research"
        case .communication: "Communication"
        case .administration: "Administration"
        case .uncategorized: "Uncategorized work"
        }
    }

    public var explanation: String {
        switch self {
        case .deepWork: "Work observed in explicitly recognized development tools."
        case .creativeWork: "Work observed in explicitly recognized design and media tools."
        case .research: "Work observed in explicitly recognized research tools."
        case .communication: "Work observed in explicitly recognized communication tools."
        case .administration: "Work observed in explicitly recognized planning and administration tools."
        case .uncategorized: "Work that cannot be safely categorized from the application name alone."
        }
    }
}

public struct WorkCategoryBreakdown: Identifiable, Equatable, Codable, Sendable {
    public let category: WorkCategory
    public let observedSeconds: Int

    public init(category: WorkCategory, observedSeconds: Int) {
        self.category = category
        self.observedSeconds = max(0, observedSeconds)
    }

    public var id: WorkCategory { category }
    public var observedMinutes: Int { Int((Double(observedSeconds) / 60).rounded()) }
}

public struct WorkCategoryClassifier: Sendable {
    public init() {}

    public func category(for application: String) -> WorkCategory? {
        let application = Self.normalize(application)
        guard !application.isEmpty else { return nil }

        for category in WorkCategory.allCases where category != .uncategorized {
            guard let signatures = Self.signatures[category] else { continue }
            if signatures.contains(where: { Self.matches(application, signature: $0) }) {
                return category
            }
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ application: String, signature: String) -> Bool {
        application == signature || application.hasPrefix("\(signature) ")
    }

    private static let signatures: [WorkCategory: [String]] = [
        .deepWork: [
            "android studio", "codex", "cursor", "intellij idea", "iterm", "iterm2", "pycharm",
            "terminal", "visual studio code", "warp", "webstorm", "xcode",
        ],
        .creativeWork: [
            "adobe after effects", "adobe illustrator", "adobe photoshop", "adobe premiere pro",
            "affinity designer", "affinity photo", "blender", "davinci resolve", "figma",
            "final cut pro", "keynote", "sketch",
        ],
        .research: ["devonthink", "mendeley", "papers", "zotero"],
        .communication: ["discord", "mail", "messages", "microsoft teams", "slack", "zoom"],
        .administration: ["activity monitor", "calendar", "finder", "numbers", "reminders", "system settings"],
    ]
}
