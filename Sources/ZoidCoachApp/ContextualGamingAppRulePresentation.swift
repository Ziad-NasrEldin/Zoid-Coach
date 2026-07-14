import ZoidCoachCore

struct ContextualGamingAppRulePresentation: Equatable, Sendable {
    static let builtInApplications = ["Discord", "Twitch"]

    let title: String
    let detail: String

    init(application: String, selection: ApplicationRuleCategory) {
        let name = Self.displayName(for: application)
        switch selection {
        case .automatic:
            title = "AUTO BY CONTEXT"
            detail = "\(name) counts as gaming only when its local window title or URL shows gaming. Work signals count as work; unclear future sessions stay Unknown."
        case .work:
            title = "ALWAYS WORK"
            detail = "Every future \(name) session counts as work, regardless of its local window title or URL."
        case .communication:
            title = "ALWAYS COMMUNICATION"
            detail = "Every future \(name) session counts as communication and contributes to work totals."
        case .gaming:
            title = "ALWAYS GAMING"
            detail = "Every future \(name) session counts as gaming and uses the gaming allowance."
        }
    }

    static func isSupported(_ application: String) -> Bool {
        let normalized = BehaviorPolicy.normalize(application)
        return builtInApplications.contains { BehaviorPolicy.normalize($0) == normalized }
    }

    static func identifierSuffix(for application: String) -> String {
        BehaviorPolicy.normalize(application)
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func displayName(for application: String) -> String {
        builtInApplications.first {
            BehaviorPolicy.normalize($0) == BehaviorPolicy.normalize(application)
        } ?? application
    }
}
