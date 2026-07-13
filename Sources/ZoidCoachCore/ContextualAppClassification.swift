import Foundation

public struct ContextualAppClassification: Sendable {
    public init() {}

    public func classify(
        application: String,
        windowTitle: String,
        url: String
    ) -> BehaviorClassification? {
        let application = Self.normalize(application)
        let context = Self.normalize("\(windowTitle) \(url)")
        guard isContextSensitive(application: application, context: context) else { return nil }

        if Self.containsAny(context, Self.workSignals) { return .work }
        if Self.containsAny(context, Self.gamingSignals) { return .gaming }
        if Self.containsAny(context, Self.distractionSignals) { return .distracting }
        return .unknown
    }

    private func isContextSensitive(application: String, context: String) -> Bool {
        Self.isContextSensitiveApplication(application)
            || Self.containsAny(context, ["youtube.com", "youtu.be", "notion.so", "discord.com", "slack.com"])
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func isContextSensitiveApplication(_ application: String) -> Bool {
        if application == "arc" || application.hasPrefix("arc ") { return true }
        return contextSensitiveApplications.contains(where: application.contains)
    }

    private static func containsAny(_ value: String, _ signals: [String]) -> Bool {
        signals.contains(where: value.contains)
    }

    private static let contextSensitiveApplications = [
        "brave", "chrome", "chromium", "discord", "firefox", "microsoft edge",
        "notion", "opera", "preview", "safari", "slack", "youtube",
    ]

    private static let workSignals = [
        "api reference", "client", "code review", "course", "customer", "design", "developer.",
        "documentation", "engineering", "figma", "github", "issue", "lecture", "meeting",
        "proposal", "project", "pull request", "research", "roadmap", "stackoverflow", "task",
        "workspace",
    ]

    private static let gamingSignals = [
        "battle.net", "game lobby", "gameplay", "league of legends", "minecraft", "playstation",
        "roblox", "steam", "twitch", "valorant", "xbox",
    ]

    private static let distractionSignals = [
        "explore", "for you", "home feed", "instagram", "recommendations", "reddit", "shorts",
        "tiktok", "trending", "twitter", "x.com/home",
    ]
}
