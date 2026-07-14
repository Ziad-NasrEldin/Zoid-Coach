import Foundation

public struct ContextualDomainRule: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayPattern: String
    public let classification: BehaviorClassification
    public let explanation: String

    fileprivate let matchText: String
    fileprivate let isReviewableDomainRule: Bool

    fileprivate init(
        id: String,
        matchText: String,
        displayPattern: String? = nil,
        classification: BehaviorClassification,
        explanation: String,
        isReviewableDomainRule: Bool
    ) {
        self.id = id
        self.matchText = matchText
        self.displayPattern = displayPattern ?? matchText
        self.classification = classification
        self.explanation = explanation
        self.isReviewableDomainRule = isReviewableDomainRule
    }

    fileprivate func matches(_ context: String) -> Bool {
        context.contains(matchText)
    }
}

public enum ContextualClassificationRuleCatalog {
    public static let domainRules = orderedRules.filter(\.isReviewableDomainRule)

    fileprivate static let orderedRules: [ContextualDomainRule] = [
        rule("work-api-reference", "api reference", .work),
        rule("work-client", "client", .work),
        rule("work-code-review", "code review", .work),
        rule("work-course", "course", .work),
        rule("work-customer", "customer", .work),
        rule("work-design", "design", .work),
        rule("work-developer", "developer.", .work, displayPattern: "developer.*", reviewable: true),
        rule("work-documentation", "documentation", .work),
        rule("work-engineering", "engineering", .work),
        rule("work-figma", "figma", .work, reviewable: true),
        rule("work-github", "github", .work, reviewable: true),
        rule("work-issue", "issue", .work),
        rule("work-lecture", "lecture", .work),
        rule("work-meeting", "meeting", .work),
        rule("work-proposal", "proposal", .work),
        rule("work-project", "project", .work),
        rule("work-pull-request", "pull request", .work),
        rule("work-research", "research", .work),
        rule("work-roadmap", "roadmap", .work),
        rule("work-stackoverflow", "stackoverflow", .work, reviewable: true),
        rule("work-task", "task", .work),
        rule("work-workspace", "workspace", .work),
        rule("gaming-battle-net", "battle.net", .gaming, reviewable: true),
        rule("gaming-game-lobby", "game lobby", .gaming),
        rule("gaming-gameplay", "gameplay", .gaming),
        rule("gaming-league-of-legends", "league of legends", .gaming),
        rule("gaming-minecraft", "minecraft", .gaming),
        rule("gaming-playstation", "playstation", .gaming, reviewable: true),
        rule("gaming-roblox", "roblox", .gaming),
        rule("gaming-steam", "steam", .gaming, reviewable: true),
        rule("gaming-twitch", "twitch", .gaming, reviewable: true),
        rule("gaming-valorant", "valorant", .gaming),
        rule("gaming-xbox", "xbox", .gaming, reviewable: true),
        rule("distraction-explore", "explore", .distracting),
        rule("distraction-for-you", "for you", .distracting),
        rule("distraction-home-feed", "home feed", .distracting),
        rule("distraction-instagram", "instagram", .distracting, reviewable: true),
        rule("distraction-recommendations", "recommendations", .distracting),
        rule("distraction-reddit", "reddit", .distracting, reviewable: true),
        rule("distraction-shorts", "shorts", .distracting),
        rule("distraction-tiktok", "tiktok", .distracting, reviewable: true),
        rule("distraction-trending", "trending", .distracting),
        rule("distraction-twitter", "twitter", .distracting, reviewable: true),
        rule("distraction-x-home", "x.com/home", .distracting, reviewable: true),
    ]

    private static func rule(
        _ id: String,
        _ matchText: String,
        _ classification: BehaviorClassification,
        displayPattern: String? = nil,
        reviewable: Bool = false
    ) -> ContextualDomainRule {
        ContextualDomainRule(
            id: id,
            matchText: matchText,
            displayPattern: displayPattern,
            classification: classification,
            explanation: explanation(for: classification),
            isReviewableDomainRule: reviewable
        )
    }

    private static func explanation(for classification: BehaviorClassification) -> String {
        switch classification {
        case .work:
            "Matches a built-in work or research destination signal."
        case .gaming:
            "Matches a built-in gaming destination signal."
        case .distracting:
            "Matches a built-in feed or entertainment destination signal."
        case .idle, .unknown:
            "Does not create a contextual classification."
        }
    }
}

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

        if let rule = ContextualClassificationRuleCatalog.orderedRules.first(where: { $0.matches(context) }) {
            return rule.classification
        }
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

}
